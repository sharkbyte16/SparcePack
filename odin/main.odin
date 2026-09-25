package sparce

import "core:fmt"
import "core:os"

spp : SparsePacker

main :: proc() {

    init_header(&spp)

    get_params(&spp)
    if spp.app_options.verbose {
        fmt.printfln("%s version %s [build %s]. %s", PACKNAME, PACKVER, build_date(), PACKCR)
    }

    if spp.app_options.action == "pack" {

        probe_pack_infile(&spp)
        // init the buffer
        spp.buff = make([dynamic]u8, spp.header.blocksize)
        create_outfile(&spp)
        spp_pack(&spp)

        if spp.app_options.check_packed {

            // force OS to flush data to physical disk
            err := os.flush(spp.fs_out)
            check_fatal_io_err(err, "io flush")
            // close the open files
            if spp.fs_out != nil {
                err := os.close(spp.fs_out)
                check_fatal_io_err(err, "close")
                spp.fs_out = nil
            }
            if spp.fs_in != nil {
                err := os.close(spp.fs_in)
                check_fatal_io_err(err, "close")
                spp.fs_in = nil
            }
            // set the input_file to the previously packed output_file and do an unpack without writing to file
            spp.app_options.input_file = spp.app_options.output_file
            probe_unpack_infile(&spp)
            resize(&spp.buff, spp.header.blocksize)
            spp.zerobuff = make([dynamic]u8, spp.header.blocksize)
            spp_unpack(&spp, true)
        }

    } else {
        probe_unpack_infile(&spp)
        spp.buff = make([dynamic]u8, spp.header.blocksize)
        spp.zerobuff = make([dynamic]u8, spp.header.blocksize)
        create_outfile(&spp)
        spp_unpack(&spp, false)
    }

    // clean up files
    if spp.fs_out != nil {
        err := os.flush(spp.fs_out)
        check_fatal_io_err(err, "io flush")
        err = os.close(spp.fs_out)
        check_fatal_io_err(err, "close")
        spp.fs_out = nil
    }
    if spp.fs_in != nil {
        err := os.close(spp.fs_in)
        check_fatal_io_err(err, "close")
        spp.fs_in = nil
    }
    
    if spp.app_options.verbose {
        fmt.println("Done.")
    }
}
