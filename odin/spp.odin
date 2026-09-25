/*###############################################################################

 Sparce Pack File format:
 +------------------------+
 | File header            |
 | Header CRC32           |
 | Duplicate header       |
 | Duplicate header CRC32 |
 +------------------------+
 | sparce                 |
 | [Block data]           |
 | sparce                 |
 | [Block data]           |
 | ...                    |
 +------------------------+

 File Header:
    magic        :  6 bytes : 'SPRSPK'
    version      :  2 bytes : [2]u8
    blocksize    :  4 bytes : u32
    org_size     :  8 bytes : i64
    nr_block     :  8 bytes : i64
    last_block   :  4 bytes : u32
    md5_hash     : 16 bytes : [16]u8

 Header CRC32 :  4 bytes : u32

 sparce         : 1 byte : u8
 Block data     : [blocksize]u8

###############################################################################*/

package sparce

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"
import "core:mem"
import "core:hash"
import "core:crypto/legacy/md5"

Header :: struct #packed {
    magic       : [len(PACKMAGIC)]u8,
    version     : [2]u8,
    blocksize   : i32,
    org_size    : i64,
    nr_blocks   : i64,
    last_block  : u32,
    md5_hash    : MD5_digest,
}

Block :: [dynamic]u8

SparsePacker :: struct {
    app_options : AppOptions,
    header   : Header,
    fs_in     : ^os.File,
    fs_out    : ^os.File,
    buff     : Block,
    zerobuff : Block,
}


init_header :: proc(sp : ^SparsePacker) {
    copy(sp.header.magic[:], PACKMAGIC)

    pv := PACKVER
    dot := strings.index_byte(pv, '.')
    assert(dot >= 0, "PACKVER missing '.'")

    maj, ok1 := strconv.parse_int(pv[:dot])
    min, ok2 := strconv.parse_int(pv[dot+1:])
    assert(ok1 && ok2, "invalid PACKVER format")
    sp.header.version[0] = u8(maj)
    sp.header.version[1] = u8(min)

    sp.header.blocksize   = PACKBLKSIZE
}


print_header :: proc(sp : SparsePacker) {
    fmt.printfln("  Magic     %s", string(PACKMAGIC))
    fmt.printfln("  Version   %v.%v", sp.header.version[0],sp.header.version[1])
    fmt.printfln("  OrgSize   %v", sp.header.org_size)
    fmt.printfln("  BlockSize %v", sp.header.blocksize)
    fmt.printfln("  NrBlocks  %v", sp.header.nr_blocks)
    fmt.printfln("  LastBlock %v", sp.header.last_block)
    fmt.printf("  MD5Hash   ")
    for i in 0..=15 {
        fmt.printf("%x", sp.header.md5_hash[i])
    }
    fmt.println()
}


get_params :: proc(sp : ^SparsePacker) {
    sp.app_options = get_options()
    sp.header.blocksize = sp.app_options.blocksize
}


create_outfile :: proc(sp : ^SparsePacker) {
    outfilename := sp.app_options.output_file
    if sp.app_options.verbose {
        fmt.println("* Creating outpute file:",outfilename)
    }

    if os.exists(outfilename) && !sp.app_options.force_overwrite {
        fmt.printfln("Output file %s exists, use option -f to force overwrite.", outfilename)
        os.exit(1)
    }

    err : os.Error
    sp.fs_out, err = os.open(outfilename, os.O_CREATE | os.O_RDWR | os.O_TRUNC)
    check_fatal_io_err(err, "open")
}

// --- pack routines ----------------------------------------------------------

probe_pack_infile :: proc(sp : ^SparsePacker) {
    infilename := sp.app_options.input_file
    if sp.app_options.verbose {
        fmt.println("* Probing:",infilename,"...")
    }
    err : os.Error
    sp.fs_in, err = os.open(infilename, os.O_RDONLY)
    check_fatal_io_err(err, "open")

    size, size_err := os.file_size(sp.fs_in)
    check_fatal_io_err(size_err, "get size")
    if size == 0 {
        fmt.println("Empty file %s: Nothing to pack", infilename)
        os.exit(0)
    }

    hash := dummy_md5_hash() // postponed to processing file

    sp.header.org_size   = size
    sp.header.nr_blocks  = ceil_div(sp.header.org_size, i64(sp.header.blocksize))
    sp.header.last_block = u32(sp.header.org_size - (sp.header.nr_blocks-1) * i64(sp.header.blocksize))
    sp.header.md5_hash   = hash

    if DEBUG && sp.app_options.verbose {
        print_header(sp^)
    }
}


is_zero_block :: proc(buffer: Block) -> bool {
    return mem.check_zero(buffer[:])
}


spp_pack :: proc(sp : ^SparsePacker) {

    sparce : u8
    err : os.Error
    bytes_written : int

    if sp.app_options.verbose {
        fmt.printf("* Packing: %s: ", sp.app_options.input_file)
    }

    crc := crc32_of_struct(&sp.header)

    // write out header (still with dummy hash) and duplicate
    bytes_written, err = write_struct(sp.fs_out, &sp.header)
    bytes_written, err = write_struct(sp.fs_out, &crc)
    bytes_written, err = write_struct(sp.fs_out, &sp.header)
    bytes_written, err = write_struct(sp.fs_out, &crc)
    check_fatal_io_err(err, "write")

    md5_context: md5.Context
    md5.init(&md5_context)
    
    // Just to be sure the file is reset
    os.seek(sp.fs_in, 0, .Start)

    // Write every full-size block
    for block_nr in 0..<sp.header.nr_blocks-1 {

        nr_bytes_read : int
        nr_bytes_read, err = os.read(sp.fs_in, sp.buff[:])
        check_fatal_io_err(err, "read")
        if nr_bytes_read == 0 {
            fmt.eprintfln("Error packing -- file truncated file during reading", sp.app_options.input_file)
            os.exit(1)
        }

        md5.update(&md5_context, sp.buff[:nr_bytes_read])

        if is_zero_block(sp.buff) {
            sparce = 1
        } else {
            sparce = 0
        }

        // write out sparce indicator
        _, err = os.write(sp.fs_out, []u8{sparce})
        check_fatal_io_err(err, "write")

        // only write out non-sparce block
        if sparce == 0 {
            _, err = os.write(sp.fs_out, sp.buff[:])
            check_fatal_io_err(err, "write")
            }
        if sp.app_options.verbose {
            pct_progress(block_nr, sp.header.nr_blocks-2)
        }
    }
    // Read and write the final (possibly partial) block
    nr_bytes_read : int
    nr_bytes_read, err = os.read(sp.fs_in, sp.buff[:])
    check_fatal_io_err(err, "read")

    md5.update(&md5_context, sp.buff[:nr_bytes_read])

    if nr_bytes_read > 0 {

        if is_zero_block(sp.buff) {
            sparce = 1
        } else {
            sparce = 0
        }
        _, err = os.write(sp.fs_out, []u8{sparce})
        check_fatal_io_err(err, "write")

        if sparce == 0 {
            _, err = os.write(sp.fs_out, sp.buff[:nr_bytes_read])
            check_fatal_io_err(err, "write")
        }

    }

    // done writing out --> update hash in header --> overwrite header in file
    hash : MD5_digest
    md5.final(&md5_context, hash[:])
    sp.header.md5_hash = hash

    os.seek(sp.fs_out, 0, .Start)

    crc = crc32_of_struct(&sp.header)

    // write out header with actual hash and duplicate
    bytes_written, err = write_struct(sp.fs_out, &sp.header)
    bytes_written, err = write_struct(sp.fs_out, &crc)
    bytes_written, err = write_struct(sp.fs_out, &sp.header)
    bytes_written, err = write_struct(sp.fs_out, &crc)
    check_fatal_io_err(err, "write")

    packed_size, size_out_err := os.file_size(sp.fs_out)
    check_fatal_io_err(size_out_err, "get size")

    if sp.app_options.verbose {
        fmt.println()
        compression := packed_size*100 / sp.header.org_size
        reduction := 100-compression
        fmt.printfln("* Compression achieved: %v%% (-%v%%)", compression, reduction)
    }

}

// --- unpack routines --------------------------------------------------------

probe_unpack_infile :: proc(sp : ^SparsePacker) {
    infilename := sp.app_options.input_file
    if sp.app_options.verbose {
        fmt.printfln("* Probing: %s ...", infilename)
    }

    err : os.Error
    sp.fs_in, err = os.open(infilename, os.O_RDONLY)
    check_fatal_io_err(err, "open")

    size, size_err := os.file_size(sp.fs_in)
    check_fatal_io_err(size_err, "get size")
    if size == 0 {
        fmt.println("Empty file %s: Nothing to pack", infilename)
        os.exit(0)
    }

    // check magic file marker
    nr_bytes_read : int
    magic : [len(PACKMAGIC)]u8
    nr_bytes_read, err = os.read(sp.fs_in, magic[:])
    check_fatal_io_err(err, "read")

    if string(magic[:]) != PACKMAGIC {
        fmt.eprintfln("%s : Not a SparcePacked file", infilename)
        os.exit(1)
    }

    // reset file pointer
    os.seek(sp.fs_in, 0, .Start)

    // read headers and CRCs
    header1, header2 : Header
    crc1, crc2 : u32
    bytes_read : int
    bytes_read, err = read_struct(sp.fs_in, &header1)
    bytes_read, err = read_struct(sp.fs_in, &crc1)
    bytes_read, err = read_struct(sp.fs_in, &header2)
    bytes_read, err = read_struct(sp.fs_in, &crc2)
    check_fatal_io_err(err, "read")

    // Check CRCs
    crc_calc1 := crc32_of_struct(&header1)
    crc_calc2 := crc32_of_struct(&header2)
    sp.header = header1
    if crc_calc1 != crc1 {
        fmt.println("Error: Corrupt file header, tryin to recover...")
        // Use duplicate header
        sp.header = header2
        if crc_calc2 != crc2 {
            fmt.eprintln("Fatal error: unable to recover file header.")
            os.exit(1)
        }
        fmt.println("File header recovery Successfully.")
    }
    // some header sanity checks
    header_error := false
    if sp.header.org_size <= 0 || sp.header.blocksize <= 0 || sp.header.nr_blocks <= 0 || sp.header.last_block <= 0 do header_error = true
    if sp.header.blocksize > MAXBLKSIZE || sp.header.blocksize < MINBLKSIZE do header_error = true
    if sp.header.org_size != i64(sp.header.blocksize)*(sp.header.nr_blocks-1) + i64(sp.header.last_block) do header_error = true
    if (i64(sp.header.blocksize) > sp.header.org_size) && (i64(sp.header.last_block) != sp.header.org_size) do header_error = true
    if check_hash(sp.header.md5_hash, dummy_md5_hash()) do header_error = true

    if header_error {
        fmt.eprintln("Error: Corrupt file header.")
        os.exit(1)
    }

    if DEBUG && sp.app_options.verbose {
        print_header(sp^)
    }
}

spp_unpack :: proc(sp : ^SparsePacker, no_write : bool) {
    block_data_size : int;
    block_nr : i64 = 0

        if sp.app_options.verbose {
            if no_write {
                fmt.printf("* Running check on: %s: ", sp.app_options.input_file)
            } else {
                fmt.printf("* Unpacking: %s: ", sp.app_options.input_file)
            }
        }

        md5_context: md5.Context
        md5.init(&md5_context)

        for {
            sparce : u8
            nr_bytes_read, err := read_struct(sp.fs_in, &sparce)

            if nr_bytes_read == 0 {
                fmt.eprintfln("Error unpacking -- file truncated file during reading", sp.app_options.input_file)
                os.exit(1)
            }

            // The last block may be shorter than BlockSize; every other block is full-size.
            if block_nr == sp.header.nr_blocks - 1 {
                block_data_size = int(sp.header.last_block)
            } else {
                block_data_size = int(sp.header.blocksize)
            }

            if sparce == 0 {
                // write non-sparce block
                nr_bytes_read, err = os.read(sp.fs_in, sp.buff[:])
                if nr_bytes_read == 0 {
                    break
                }
                if no_write == false {
                    _, err = os.write(sp.fs_out, sp.buff[:nr_bytes_read])
                    check_fatal_io_err(err, "write")
                }
                md5.update(&md5_context, sp.buff[:nr_bytes_read])

            } else {
                // write sparce block, using the correct size for the last block
                if no_write == false {
                    _, err = os.write(sp.fs_out, sp.zerobuff[:block_data_size])
                    check_fatal_io_err(err, "write")
                }
                md5.update(&md5_context, sp.zerobuff[:block_data_size])
            }

            block_nr += 1

            if sp.app_options.verbose {
                pct_progress(block_nr, sp.header.nr_blocks)
            }

            if block_nr == sp.header.nr_blocks {
                break
            }
        }


        if sp.app_options.verbose do fmt.println()

        hash : MD5_digest
        md5.final(&md5_context, hash[:])

        if check_hash(hash, sp.header.md5_hash) {
            if sp.app_options.verbose && no_write == true  {
                fmt.println("* Check successful")
            }
            if sp.app_options.verbose && no_write == false {
                fmt.printfln("* Successfully unpacked %s --> %s", sp.app_options.input_file, sp.app_options.output_file)
            }
        } else {
            fmt.printfln("!!! Error unpacking %s. Original content not recovered !!!", sp.app_options.output_file)
            os.exit(1)
        }

}