#if OS == {
    case .LINUX; #load "platform_linux.jai";
    case .MACOS; #load "platform_macos.jai";
}

Platform_Resize_Callback :: #type (window: Window_Type, width: int, height: int); 
