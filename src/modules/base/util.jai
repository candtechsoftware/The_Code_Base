kilobyte :: inline (n: $T)-> T {
    return n << 10;
}

kilbyte :: inline (n: $T)-> T {
    return n << 10;
}

megbyte :: inline (n: $T) -> T {
  return n << 20;
}


clamp_top :: inline (a: $t, x: t) -> t {
    return min(a, x);
}

clamp_bot :: inline (x: $t, b: t) -> t {
    return max(x, b);
}


memory_zero :: inline (s: *void, z: s64) {
    memset(s, 0, z);
}

memory_zero_struct :: inline (s: *$t) {
    memset(s, 0, size_of(t));
}

memory_copy :: inline (dst: *void, src: *void, size: s64) {
    memcpy(dst, src, size);
}

memory_set :: inline (dst: *void, byte: u8, size: s64) {
    memset(dst, byte, size);
}

memory_compare :: inline (a: *void, b: *void, size: s64) -> s32 {
    return memcmp(a, b, size);
}

align_pow2 :: inline (x: u64, b: u64) -> u64 {
    return (x + b - 1) & ~(b - 1);
}


#import "Basic";
#import "Math";
