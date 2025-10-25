kilabyte :: inline (n: u64) -> u64{
    return n << 10;
}

megabyte :: inline (n: u64) -> u64 {
  return n << 20;
}

gigabyte :: inline (n: u64) -> u64 {
  return n << 30;
}


clamp_top :: inline (a: $t, x: t) -> t {
    return min(a, x);
}

clamp_bot :: inline (x: $t, b: t) -> t {
    return max(x, b);
}

is_pos2_or_zero :: inline (x: u64) -> bool {
    return (((x)&((x)-1)) == 0);
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

align_pow2 :: inline (x: u64, b: u64) -> u64  {
    return (x + b - 1) & ~(b - 1);
}

align_up_pow2 :: inline (x: u64, p: u64) -> u64 {
    return (((x) + (p) - 1) &~((p)-1));
} 

align_down_pow2 :: inline (x: u64, p: u64) -> u64 {
    return ((x)&~((p)-1));
} 
base_array_find :: (array: [] $T, item: T) -> bool, s64 {
    for array if it == item return true, it_index;
    return false, -1;  // Not found.
}


#import "Basic";
#import "Math";


