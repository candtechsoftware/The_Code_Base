

application_initialized := false;
window_should_close := false; 
main_window: Window; 
platform_events_this_frame: [..]Event; 
platform_resize_cb: Platform_Resize_Callback;

init_app :: () {
    if application_initialized return; 
    application_initialized = true; 
} 


platform_create_window :: (width: int, height: int, title: string) -> Window_Type, bool {
    init_app();

    window := create_window(width, height, title); 
    main_window := xx window; 

    XFlush(x_global_display); 
    XSync(x_global_display, False); // @TODO Turns off vsync should be a config; 

    exposed := false; 

    for i: 0..100 {
        while XPending(x_global_display) > 0 {
            event: XEvent; 
            XNextEvent(x_global_display, *event); 
            if event.type == Expose && event.xexpose.window == window {
                exposed = true; 
                break; 
            } 
        } 
    } 
    return xx window, true; 
} 

platform_get_window_size :: (window: Window_Type) -> (s32, s32, s32, s32, bool) { 
    x, y, w, h, ok := get_dimensions(xx window, false);
    return x, y, w, h, ok; 
}


platform_process_events_this_frame :: () {
    update_window_events(); 
    array_copy(*platform_events_this_frame, events_this_frame); 
    for get_window_resizes() {
        if it.window == main_window {
            if platform_resize_cb {
                platform_resize_cb(xx main_window, it.width, it.height); 
            } 
        } 
    } 
} 

platform_window_should_close :: () -> bool {
    return window_should_close; 
} 

platform_get_mouse_pointer_position :: (window: Window_Type, right_handed: bool) -> int, int, bool {
    x, y, ok := get_mouse_point_position(xx window, right_handed); 
    return x, y, ok; 
} 

platform_get_dpi_scale :: (window: Window_Type) -> float {
    if !x_global_display return 1.0;
    screen     := DefaultScreen(x_global_display); 
    width_px   := XDisplayWidth(x_global_display, screen);
    height_px  := XDisplayHeight(x_global_display, screen);
    width_mm   := XDisplayWidthMM(x_global_display, screen);
    height_mm  := XDisplayHeightMM(x_global_display, screen);

    if width_mm <= 0 || height_mm <= 0 return 1.0; 

    dpi_x := cast(float) width_px * 25.4 / cast(float) width_mm;
    dpi_y := cast(float) height_px * 25.4 / cast(float) height_mm;
    dpi := (dpi_x + dpi_y) / 2.0;
    
    scale := dpi / 96.0;
    
    if scale < 0.5 scale = 0.5;
    if scale > 4.0 scale = 4.0;
    
    return scale;
}



platform_shutdown :: () {
    application_initialized = false;
    window_should_close = false; 
} 


#import "Window_Creation"; 
#import "X11";
#import "Basic";
#import "Input"; 

