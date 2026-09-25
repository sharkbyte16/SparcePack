package sparce

import "core:hash"
import "core:mem"

MD5_digest :: [16]u8


dummy_md5_hash :: proc() -> MD5_digest {
    return 0xff     // auto-fils the MD5_digest array
}


check_hash :: proc(hash, header_hash : MD5_digest) -> bool {
    ok := true
    for i in 0..=15 {
        if hash[i] != header_hash[i] {
            ok = false
        }
    }
    return ok
}


crc32_of_struct :: proc(val: ^$T) -> u32 {
    data := mem.byte_slice(val, size_of(T))
    return hash.crc32(data)
}