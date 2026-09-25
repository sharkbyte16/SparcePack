package sparce

import "core:fmt"
import "core:strings"
import "core:time"
import "core:os"
import "core:mem"

spinner_chars : [4]int = {124,47,45,92}

spinner :: proc() {
    @static idx : int = 0
    fmt.print(rune(spinner_chars[idx]))
    fmt.print(rune(8)) // backspace
    idx = (idx+1) %% 4
}

pct_progress :: proc(i, tot : i64) {
    pct := 100*i / tot
    // workaround for zero padding quick of Odin
    if pct == 100 {        
    } else if pct < 10 {
        fmt.print("  ")        
    } else {
        fmt.print(" ")        
    }
    // workaround for space inserts when combined in single print statement
    fmt.print(pct) 
    fmt.print("%")
    fmt.print(rune(8))
    fmt.print(rune(8))
    fmt.print(rune(8))
    fmt.print(rune(8))
}

extract_file_ext :: proc(filename : string) -> (basename : string, ext : string) {
    // Find the index of the last occurrence of '.'
    index := strings.last_index(filename, ".")

    // assume no extension
    basename = filename
    ext = ""
    // correct if present
    if index != -1 {
        // To get the extension (including the period):
        basename = filename[:index]
        ext = filename[index:]
    }
    
    return basename, ext
}

strip_dashes :: proc(s: string, out: []u8) -> string {
    n := 0
    for c in s {
        if c != '-' {
            out[n] = u8(c)
            n += 1
        }
    }
    return string(out[:n])
}

build_date :: proc() -> string {
    t := time.unix(0, ODIN_COMPILE_TIMESTAMP) // sec=0, nanos=timestamp
    buf: [time.MIN_YYYY_DATE_LEN]u8
    date_str := time.to_string_yyyy_mm_dd(t, buf[:])
    out: [8]u8
    yyyymmdd := strip_dashes(date_str, out[:])    
    return strings.clone(yyyymmdd)
}

ceil_div :: proc(a, b: i64) -> i64 {
    return (a + b - 1) / b
}

read_struct :: proc(f: ^os.File, val: ^$T) -> (int, os.Error) {
    data := mem.byte_slice(val, size_of(T))
    bytes_read, err := os.read(f, data)
    return bytes_read, err
}

write_struct :: proc(f: ^os.File, val: ^$T) -> (int, os.Error) {
    data := mem.byte_slice(val, size_of(T))
    bytes_written, err := os.write(f, data)
    return bytes_written, err
}

check_fatal_io_err :: proc(err : os.Error, io_action: string) {
    if err != nil {
        fmt.eprintfln("Failed to %s file: %v", io_action, err)
        os.exit(1)
    }
}