#if OS == {
    case .LINUX; #load "platform_linux.jai";
    case .MACOS; #load "platform_macos.jai";
}


Platform_Kind :: enum {
    MACOS;
    LINUX; 
    WINDOWS;
} 
Platform_Handle :: struct {
    kind: Platform_Kind = .MACOS;
    union {
        window_type: Window_Type;
        ptr:         *void;
        u64s:        [1]u64;
        u32s:        [2]u32; 
        u16s:        [4]u16; 
    }
} 

operator ! :: inline (a: Platform_Handle) -> bool {
    return a.ptr == null;
} 

operator == :: inline (a: Platform_Handle, b: Platform_Handle) -> bool {
    return a.window_type == b.window_type || a.ptr == b.ptr;
} 

operator == :: inline (a: Platform_Handle, b: Window_Type) -> bool {
    return a.window_type == b;
} 

Platform_Resize_Callback :: #type (window: Platform_Handle, width: int, height: int); 
