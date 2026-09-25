package sparce

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:slice"

AppOptions :: struct {
    input_file : string,
    output_file : string,
    force_overwrite : bool, 
    check_packed : bool,
    verbose : bool,
    help: bool,
    action : string,         // pack | unpack
    blocksize : i32,         // -1 = not set
}

usage :: proc() {
    fmt.printfln("%s version %s [build %s]. %s", PACKNAME, PACKVER, build_date(), PACKCR)
    fmt.println("Packs a sparce file or inflates a packed file.")
    fmt.println()
    fmt.println("sparce [options] <inputfile> [options]")
    fmt.println()
    fmt.println("Options:")
    fmt.println("       -o, --outfile <FILE>            Write output to FILE")
    fmt.println("       -b, --blocksize <SIZE>          Use blocks of SIZE bytes for packing")
    fmt.println("       -f, --force                     Overwrite an existing output file")
    fmt.println("       -c, --check                     Validate that packed file unpacks to original")
    fmt.println("       -v, --verbose                   Print additional information")
    fmt.println("       -h, --help                      Show this help message and exit")
    fmt.println()
}

parse_opts :: proc(app_opts: ^AppOptions) -> string {
    // Initialize defaults
    app_opts.input_file = ""
    app_opts.output_file = ""
    app_opts.force_overwrite = false
    app_opts.check_packed = false
    app_opts.verbose = false
    app_opts.help = false
    app_opts.action = "pack"
    app_opts.blocksize = -1

    opt :: struct{
       flag : string,
       long_flag : string,
       present : bool,
       arg : string,
    }

    flag :: struct{
       flag : string,
       long_flag : string,
       present : bool,
    }

    // array for options that have one value argument
    opts := make([dynamic]opt)
    defer delete(opts)

    // array for flags without value argument
    flags := make([dynamic]flag)
    defer delete(flags)

    // array for positional arguments
    pos_args := make([dynamic]string)
    defer delete(pos_args)    

    // define option here
    append(&opts, opt{"-o", "--outfile",   false, ""})
    append(&opts, opt{"-b", "--blocksize", false, ""})

    // define flags here
    append(&flags, flag{"-f", "--force"  , false})
    append(&flags, flag{"-c", "--check"  , false})
    append(&flags, flag{"-v", "--verbose", false})
    append(&flags, flag{"-h", "--help", false})

    // array of the args
    args := make([dynamic]string)
    defer delete(args)

    // get the arguments from os
    for i in 1..<len(os.args) {
        append(&args, os.args[i])
    }

    index := -1
    // process all flag arguments

    for i in 0..<len(flags) {

        // is the flag present?
        index_short, found_short := slice.linear_search(args[:], flags[i].flag)
        if index_short != -1 do index = index_short        
        index_long, found_long := slice.linear_search(args[:], flags[i].long_flag)
        if index_long != -1 do index = index_long

        if !found_short && !found_long { 
            continue
        }

        // and not double specified?
        if found_short && found_long {
            return fmt.tprintf("Cannot specify both short and long form flags: %s and %s", flags[i].flag, flags[i].long_flag)
        }
        
        // and is the next argument an option or flag? (if not --> error)
        if found_short && (index_short < len(args)-1) {
            s := args[index_short + 1]            
            if s[0:1] != "-" {
                return fmt.tprintf("Short flag %s does not take argument %s", flags[i].flag, s)
            }
            index = index_short
        }
        if found_long && (index_long < len(args)-1) {
            s := args[index_long + 1]
            if s[0:1] != "-" {
                return fmt.tprintf("Long flag %s does not take argument %s", flags[i].long_flag, s)
            }
            index = index_long
        }
        
        // ok, found a flag, set it and remove from the arg list
        flags[i].present = true
        ordered_remove(&args, index)
    }

    // if -h, --help, show help and exit
    if flags[3].present {
        usage()
        os.exit(0)
    }

    // process all options
    for i in 0..<len(opts) {

        // is the opt present?
        index_short, found_short := slice.linear_search(args[:], opts[i].flag)
        index_long, found_long := slice.linear_search(args[:], opts[i].long_flag)
        if !found_short && !found_long { 
            continue
        }

        // and not double specified?
        if found_short && found_long {
            return fmt.tprintf("Cannot specify both short and long form options: %s and %s", opts[i].flag, opts[i].long_flag)
        }
        
        // and opt not last argument?
        if (index_short == len(args)-1) || (index_long == len(args)-1) {
            return fmt.tprintf("Option %s takes an argument", opts[i].flag)
        }

        // and is the next argument an option or flag? (if yes --> error)
        if found_short && (index_short < len(args)-1) {
            s := args[index_short + 1]
            if s[0:1] == "-" {
                return fmt.tprintf("Option %s takes an argument", opts[i].flag)
            }
            index = index_short
        }
        if found_long && (index_long < len(args)-1) {
            s := args[index_long + 1]
            if s[0:1] == "-" {
                return fmt.tprintf("Option %s takes an argument", opts[i].long_flag)
            }
            index = index_long
        }
        
        // ok, found an opt, set it and remove from the arg list        
        opts[i].present = true
        opts[i].arg = args[index+1]
        ordered_remove(&args, index)
        ordered_remove(&args, index)
    }

    // now the positional arguments are left, should only be one (input filename)
    for i in 0..<len(args){
        append(&pos_args, args[i])
    }
    if len(pos_args) < 1{
        return "Missing <inputfile>"
    }
    if len(pos_args) > 1 {
        return fmt.tprintf("Unknown arguments: %v", pos_args[1:])
    }

    // parsing ok, lets set the options
    // ! note the order of the above defined options and flags !    

    // -o output file
    if opts[0].present {         
        app_opts.output_file = opts[0].arg
    }

    // -b blocksize
    if opts[1].present {        
        val, ok := strconv.parse_int(opts[1].arg)
        if !ok { 
            return fmt.tprintf("Invalid block size %s", opts[1].arg) 
        }
        ival := i32(val)
        if ival != -1 && ival <= 0 { 
            return "Block size must be a positive integer." 
        }
        app_opts.blocksize = ival
    }    

    // -f -c -v -h
    app_opts.force_overwrite = flags[0].present
    app_opts.check_packed    = flags[1].present
    app_opts.verbose         = flags[2].present
    app_opts.help            = flags[3].present

    // input filename
    app_opts.input_file = pos_args[0]
    if app_opts.input_file == "" {
        return "Inputfile cannot be empty."
    }

    // all done
    return ""
}

get_options :: proc() -> AppOptions {
    opts: AppOptions
    
    if err := parse_opts(&opts); err != "" {
        usage()
        fmt.eprintln("Error:", err)
        os.exit(1)
    }

    if opts.blocksize == -1 {
        opts.blocksize = PACKBLKSIZE
    }

    // input file extension
    in_name, in_ext := extract_file_ext(opts.input_file)
    
    if strings.to_lower(in_ext) == PACKEXT {
        // We are unpacking
        opts.action = "unpack"

        // Output filename not specified --> remove extension from the input filename
        if opts.output_file == "" {
            opts.output_file = in_name
        }
        
        // If output extension is PACKEXT --> append 'unpacked'
        _ , out_ext := extract_file_ext(opts.output_file)
        if strings.to_lower(out_ext) == PACKEXT {
            opts.output_file = fmt.tprintf("%s.unpacked", opts.output_file)
        }
        
        if opts.check_packed {
            fmt.println("Note: -c only applies when packing; ignored for unpacking.")
        }
    } else {
        // We are packing
        opts.action = "pack"
        
        // Output filename, if not specified append extension to input filename
        if opts.output_file == "" {
            opts.output_file = fmt.tprintf("%s%s", opts.input_file, PACKEXT)
        } else {
            // else check for correct extension, if not, append it
            _, out_ext := extract_file_ext(opts.output_file)
            if strings.to_lower(out_ext) != PACKEXT {
                opts.output_file = fmt.tprintf("%s%s", opts.output_file, PACKEXT)
            }
        }
    }

    return opts
}

