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


memory_zero :: inline (s: *void, z: u64) {
    memset(s, 0, z);
}

memory_zero_struct :: inline (s: *$t) {
    memset(s, 0, size_of(t));
}

memory_copy :: inline (dst: *void, src: *void, size: u64) {
    memmove(dst, src, size);
}

memory_set :: inline (dst: *void, byte: u8, size: u64) {
    memset(dst, byte, size);
}

memory_compare :: inline (a: *void, b: *void, size: u64) -> s32 {
    return memcmp(a, b, size);
}

align_pow2 :: inline (x: u64, b: u64) -> u64 {
    return (x + b - 1) & ~(b - 1);
}


#import "Basic"; 

Render_Handle :: union {
    u64s: [1]u64; 
    u32s: [2]u32;
    u16s: [3]u16;
} 

Link_List :: struct(T: Type) {
    first: *Link_List_Node(T);
    last:  *Link_List_Node(T);
} 

Link_List_Node :: struct(T: Type) {
    next: *Link_List_Node(T);
    value: T;
};

link_list_push :: (list: *Link_List, node: *Link_List_Node) {
    if list.first == null {
        list.first = node; 
        list.last = node; 
        node.next = null;
    } else {
        list.last.next = node;
        list.last = node; 
        node.next = null;
    } 
} 


link_list_print :: (list: *Link_List) {
    sb: String_Builder;
    while list.first != list.last {
        if list.first  {
            print_to_builder(*sb,"% -> ", list.first.value);
            list.first = list.first.next;
        } 
    } 
    print_to_builder(*sb,"%", list.last.value);
    str := builder_to_string(*sb);
    print("%\n",str); 
} 


#import "Basic";
#import "Math";
