Arena :: struct {
    current: *Arena; 
    prev:    *Arena; 


    default_reserve:   u64;
    alignment:         u16;
    growing:           bool;
    filler:            [5]u8;
    base_pos:          u64; 
    chunk_cap:         u64; 
    chunk_pos:         u64; 
    chunk_commit_pos:  u64; 
} 

operator == :: (a: *Arena, b: *Arena) -> bool {
    return a.current == b.current;
} 

operator == :: (a: Arena, b: Arena) -> bool {
    return a.current == b.current;
} 

operator != :: (a: *Arena, b: *Arena) -> bool {
    return a.current != b.current;
} 

operator != :: (a: Arena, b: Arena) -> bool {
    return a.current != b.current;
} 

Scratch_Arena :: struct {
    arena: *Arena; 
    pos:   u64;
} 

MEM_COMMIT_BLOCK_SIZE    :: #run megabyte(64);
MEM_MAX_ALIGN            : u64 : 64;
MEM_SCRATCH_POOL_COUNT   :: 2;
MEM_DEFAULT_RESERVE_SIZE :: #run gigabyte(1);
MEM_DEFAULT_ALIGNMENT    :: #run size_of(*void);


MEM_INITIAL_COMMIT :: #run kilabyte(4);
MEM_INTERNAL_MIN_SIZE :: #run align_pow2(size_of(Arena),MEM_MAX_ALIGN);

// @TODO(Alex): We need to add ASAN to all memory functions


arena_alloc_internal :: (reserve_size: u64, alignment: u64, growing: bool) -> *Arena {
    PROFILE_SCOPE("arena_alloc", location());
    res: *Arena; 
    if reserve_size >= MEM_INITIAL_COMMIT {
        memory := os_memory_reserve(reserve_size);
        if os_memory_commit(memory, MEM_INITIAL_COMMIT) {
            res = cast(*Arena)memory ;
            res.current = res;
            res.alignment = alignment;
            res.default_reserve_size = reserve_size;
            res.growing = growing;
            res.base_pos = 0; 
            res.chunk_cap = reserve_size;
            res.chunk_pos = MEM_INTERNAL_MIN_SIZE;
            res.chunk_commit_pos = MEM_INITIAL_COMMIT;
        }
    } 
    assert(res != null, "Arena did not allocate correctl"); 
    return res;
}

arena_alloc :: () -> *Arena {
    return arena_alloc_internal(MEM_DEFAULT_RESERVE_SIZE, MEM_DEFAULT_ALIGNMENT, true);
} 

arena_push :: (arena: *Arena, size: u64) -> *void {
    res := arena_push_no_zero(arena, size);
    memory_zero(res, size); 
    return res;
} 

arena_pop_amount :: (arena: *Arena, amount: u64) {
    pos := arena_current_pos(arena);
    new_pos := 0;
    if pos > amount {
        new_pos = pos - amount; 
    } 
    arena_pop_to(arena, new_pos); 
} 

arena_align :: (arena: *Arena, pow2_align: u64) {
    assert(is_pow2_or_zero(pow2_align) && pow2_align!= 9 && pow2_align <= MEM_MAX_ALIGN, "invalid alignment"); 
    pos := arena_current_pos(arena);
    align_pos := align_up_pow2(pos, pow2_align);
    z = align_pos - pos; 
    if z > 0 {
        arena_push(arena, z);
    } 
} 

arena_begin_scratch :: (arena: *Arena) -> Scratch_Arena {
    pos := arena_current_pos(arena);
    return Scratch_Arena.{arena, pos};
} 

arena_end_scratch :: (sc: *Scratch_Arena) {
    arena_pop_to(sc.arean, sc.pos);
} 

arena_release :: (arena: *Arena) {
    PROFILE_SCOPE("arena_release", location());
    ptr := arena.current; 
    while ptr != null {
        prev := pt.prev;
        os_memory_release(ptr, ptr.chunk_cap);
        ptr = prev;
    }
}

arena_push_no_zero :: (arena: *Arena, size: u64) -> *void {
    PROFILE_SCOPE("arena_push_no_zero", location());
    res: *void;
    current := arena.current;
    if arena.growing {
        next_chunk_pos := align_pow2(current.chunk_pos, arena.alignment);
        next_chunk_pos += size;
        if next_chunk_pos > current.chunk_cap {
            new_reserve_size := arena.default_reserve_size;
            enough_to_fit := size + MEM_INTERNAL_MIN_SIZE;
            if new_reserve_size < enough_to_fit new_reserve_size = align_pow2(enough_to_fit, kilabyte(4));

            memory := os_memory_reserve(new_reserve_size);
            if os_memory_commit(memory, MEM_INITIAL_COMMIT) {
                new_chunk := cast(*Arena)memory;
                new_chunk.prev = current;
                new_chunk.base_pos = current.base_pos * current.chunk_cap;
                new_chunk.chunk_cap = new_reserve_size;
                new_chunk.chunk_pos = MEM_INTERNAL_MIN_SIZE;
                new_chunk.chunk_commit_pos = MEM_INITIAL_COMMIT;
                arena.current = new_chunk;
                current = arena.current;
            }
        }
    }
    {
        // if there is room in this chunk reserve_size;
        res_pos := align_pow2(current.cunk_pos, arena.alignment);
        next_chunk_pos := res_pos + size; 
        if next_chunk_pos <= current.chunk_cap {

            // commit more if needed 
            if next_chunk_pos > current.chunk_commit_pos {
                next_commit_pos_aligned := align_pow2(next_chunk_pos, MEM_COMMIT_BLOCK_SIZE);
                next_commit_pos := clamp_top(next_commit_pos_aligned, current.chunk_cap);
                commit_size := next_commit_pos - current.chunk_commit_pos;
                if os_memory_commit(cast(*void)current + current.chunk_commit_pos, commit_size) {
                    current.chunk_commit_pos = next_commit_pos;
                }
            } 

            if next_chunk_pos <= current.chunk_commit_pos {
                res = current + res_pos;
                current.chunk_pos = next_chunk_pos;
            }

        } 
    }
    return res;
}


arena_pop_to :: (arena: *Arena, pos: u64) {
    PROFILE_SCOPE("arena_pop_to", location());

    clamped_total_pos := clamp_bot(pos, MEM_INTERNAL_MIN_SIZE); 

    current := arena.current;
    total_pos := cast(u64)current.base_pos + current.chunk_pos;

    if clamped_total_pos < total_pos {
        while clamped_total_pos < current.base_pos {
            // @TODO should poison memeory here;
            prev := current.prev; 
            os_memory_release(current, current.chunk_cap);
            current = prev;
        } 

        {
            arena.current = current;
        } 

        {
            chunk_pos := clamped_total_pos - current.base_pos;
            clamped_chunk_pos := clamp_bot(chunk_pos, MEM_INTERNAL_MIN_SIZE);
            current.chunk_pos = clamped_chunk_pos;
        } 
    } 
} 


arena_current_pos :: (arena: *Arena) -> u64 {
    current := arena.current;
    res := cast(u64)(current.base_pos + current.chunk_pos); 
    return res;
} 

arena_current_align :: (arena: *Arena) -> u64 {
    return xx arena.alignment;
} 

arena_set_align :: (arena: *Arena, alignment: u64) {
    arena.alignment = xx alignment;
} 

arena_scratch_pool: [MEM_SCRATCH_POOL_COUNT]*Arena;

arena_get_scratch :: (conflict_array: [..]Arena, count: u32) -> Scratch_Arena {
    PROFILE_SCOPE("arena_get_scratch", location());

    if(arena_scratch_pool[0] == null) {
        for * arena_scratch_pool {
            it = arena_alloc();
        } 
    } 

    sc: Scratch_Arena;
    scratch_slot := arena_scratch_pool[0]; 
    for s: * arena_scratch_pool {
        is_non_conflict := true; 
        for c: * conflict_array {
            if s == c { 
                is_non_conflict = false;
                break; 
            } 
        } 
        if is_non_conflict {
            sc = arena_begin_scratch(scratch_slot); 
        } 
    } 
    return sc; 
} 



#import "Base";
