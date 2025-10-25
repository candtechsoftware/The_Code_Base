os_memory_reserve :: (size: u64) -> *void {
    res := mmap(null, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); 
    if (res == MAP_FAILED) {
        return null;
    } 

    return res; 
} 

os_memory_commit :: (ptr: *void, size: u64) -> bool {
    result := mprotect(ptr, size, PROT_READ | PROT_WRITE);
    return result == 0;
}


os_memory_commit_large :: (ptr: *void, size: u64)-> bool {
    return os_commit(ptr, size);
}

os_memory_decommit :: (ptr: *void, size: u64) {
    mprotect(ptr, size, PROT_NONE);
    madvise(ptr, size, MADV_DONTNEED);
}

os_memory_release :: (ptr: *void, size: u64) {
    munmap(ptr, size);
}


#import "POSIX";
