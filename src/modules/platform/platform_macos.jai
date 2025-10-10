#import "Basic";
#import "Objective_C";
#import "Objective_C/AppKit";
#import "Input";
#import "Window_Creation"; 

platform_initialized := false;
window_should_close := false;
main_window: *NSWindow;
platform_resize_cb: Platform_Resize_Callback;

OBJC_ASSOCIATION_ASSIGN :: 1;
OBJC_ASSOCIATION_RETAIN_NONATOMIC :: 1;
OBJC_ASSOCIATION_COPY_NONATOMIC :: 3;
OBJC_ASSOCIATION_RETAIN :: 0x301;
OBJC_ASSOCIATION_COPY :: 0x303;

WindowDelegate :: struct {
    #as super: NSObject;
}

window_delegate_windowWillClose :: (self: *WindowDelegate, selector: Selector, notification: *void) #c_call {
    window_should_close = true;
}

register_window_delegate :: () {
    delegate_class := objc_allocateClassPair(objc_getClass("NSObject"), "WindowDelegate", 0);
    if !delegate_class return;
    
    windowWillClose_sel := sel_registerName("windowWillClose:");
    class_addMethod(delegate_class, windowWillClose_sel, 
                    cast(*void) window_delegate_windowWillClose, "v@:@");
    
    objc_registerClassPair(delegate_class);
}

is_system_dark_mode :: () -> bool {
    NSUserDefaults_class := objc_getClass("NSUserDefaults");
    if !NSUserDefaults_class return false;
    
    standardUserDefaults_sel := sel_registerName("standardUserDefaults");
    getDefaults_func :: #type (*void, Selector) -> *void #c_call;
    defaults := (cast(getDefaults_func) objc_msgSend)(NSUserDefaults_class, standardUserDefaults_sel);
    if !defaults return false;
    
    stringForKey_sel := sel_registerName("stringForKey:");
    getString_func :: #type (*void, Selector, *NSString) -> *NSString #c_call;
    key := NSString.getTempString("AppleInterfaceStyle");
    style_string := (cast(getString_func) objc_msgSend)(defaults, stringForKey_sel, key);
    
    if !style_string return false;
    
    UTF8String_sel := sel_registerName("UTF8String");
    getUTF8_func :: #type (*void, Selector) -> *u8 #c_call;
    utf8_str := (cast(getUTF8_func) objc_msgSend)(style_string, UTF8String_sel);
    
    if utf8_str {
        str := to_string(utf8_str);
        return str == "Dark";
    }
    
    return false;
}

apply_system_appearance :: () {
    NSAppearance_class := objc_getClass("NSAppearance");
    if !NSAppearance_class return;
    
    appearance_name: *NSString;
    if is_system_dark_mode() {
        appearance_name = NSString.getTempString("NSAppearanceNameDarkAqua");
        // System is in dark mode
    } else {
        appearance_name = NSString.getTempString("NSAppearanceNameAqua");
        // System is in light mode
    }
    
    appearanceNamed_sel := sel_registerName("appearanceNamed:");
    appearanceNamed_func :: #type (*void, Selector, *NSString) -> *void #c_call;
    appearance := (cast(appearanceNamed_func) objc_msgSend)(NSAppearance_class, appearanceNamed_sel, appearance_name);
    
    if appearance {
        setAppearance_sel := sel_registerName("setAppearance:");
        setAppearance_func :: #type (*void, Selector, *void) -> void #c_call;
        set_func := cast(setAppearance_func) objc_msgSend;
        set_func(NSApp, setAppearance_sel, appearance);
    }
}

init_mac_platform :: () {
    if platform_initialized return;
    
    init_objective_c();
    init_app_kit();
    
    register_window_delegate();
    
    NSApplication.sharedApplication();
    
    apply_system_appearance();
    
    create_menu_bar();
    
    NSApplication.finishLaunching(NSApp);
    
    setActivationPolicy_sel := sel_registerName("setActivationPolicy:");
    setActivationPolicy_func :: #type (*void, Selector, s64) -> void #c_call;
    policy_func := cast(setActivationPolicy_func) objc_msgSend;
    NSApplicationActivationPolicyRegular :: 0;
    policy_func(NSApp, setActivationPolicy_sel, NSApplicationActivationPolicyRegular);
    
    NSApplication.activateIgnoringOtherApps(NSApp, YES);
    
    platform_initialized = true;
}

platform_create_window :: (width: int, height: int, title: string) -> Window_Type, bool {
    init_mac_platform();
    
    screen := NSScreen.mainScreen();
    frame: NSRect;
    frame.origin = .{0, 0};
    frame.size = .{xx width, xx height};
    
    window_style := NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | 
                   NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    
    window := NSWindow.initWithContentRect(objc_alloc(NSWindow), frame,
                window_style, NSBackingStoreBuffered, NO, screen);
    
    autorelease(window);
    NSWindow.setReleasedWhenClosed(window, NO);
    NSWindow.setTitle(window, title);
    
    setAppearance_sel := sel_registerName("setAppearance:");
    setAppearance_func :: #type (*void, Selector, *void) -> void #c_call;
    set_func := cast(setAppearance_func) objc_msgSend;
    set_func(window, setAppearance_sel, null);
    
    view := objc_init(objc_alloc(NSView));
    NSView.setWantsLayer(view, YES);
    autorelease(view);
    
    set_func(view, setAppearance_sel, null);
    
    NSWindow.setContentView(window, view);
    NSWindow.makeFirstResponder(window, view);
    
    NSWindow.setCollectionBehavior(window, NSWindowCollectionBehaviorFullScreenPrimary | NSWindowCollectionBehaviorManaged);
    
    NSWindow.center(window);
    
    NSWindow.makeKeyAndOrderFront(window, null);
    
    NSAppearance_class := objc_getClass("NSAppearance");
    if NSAppearance_class {
        appearance_name: *NSString;
        if is_system_dark_mode() {
            appearance_name = NSString.getTempString("NSAppearanceNameDarkAqua");
        } else {
            appearance_name = NSString.getTempString("NSAppearanceNameAqua");
        }
        
        appearanceNamed_sel := sel_registerName("appearanceNamed:");
        appearanceNamed_func :: #type (*void, Selector, *NSString) -> *void #c_call;
        appearance := (cast(appearanceNamed_func) objc_msgSend)(NSAppearance_class, appearanceNamed_sel, appearance_name);
        
        if appearance {
            setAppearance_sel := sel_registerName("setAppearance:");
            setAppearance_func :: #type (*void, Selector, *void) -> void #c_call;
            set_func := cast(setAppearance_func) objc_msgSend;
            set_func(window, setAppearance_sel, appearance);
        }
    }
    
    delegate_class := objc_getClass("WindowDelegate");
    if delegate_class {
        delegate := objc_init(objc_alloc(delegate_class));
        if delegate {
            setDelegate_sel := sel_registerName("setDelegate:");
            setDelegate_func :: #type (*void, Selector, *void) -> void #c_call;
            set_del_func := cast(setDelegate_func) objc_msgSend;
            set_del_func(window, setDelegate_sel, delegate);
            
            autorelease(delegate);
        }
    }
    
    NSWindow.makeKeyAndOrderFront(window, null);
    
    main_window = window;
    
    input_application_has_focus = true;
    
    
    return window, true; 
}

platform_events_this_frame: [..] Event;

platform_get_window_size :: (window: Window_Type) -> (s32, s32, s32, s32, bool)  {
    x, y, w, h, success := get_dimensions(window, false);
    return x, y, w, h, success;
}

platform_process_events_this_frame :: () {
    update_window_events();
    array_copy(*platform_events_this_frame, events_this_frame);

    for get_window_resizes() {
        if (it.window == main_window) {
            if platform_resize_cb {
                platform_resize_cb(main_window, it.width, it.height);
            } 
        } 
    } 
}

platform_get_mouse_pointer_position :: (window: Window_Type, right_handed: bool) -> int, int, bool {
   x ,y, success :=  get_mouse_pointer_position(window, right_handed);
   return x, y, success;
} 

platform_window_should_close :: () -> bool {
    return window_should_close;
}

handle_window_will_close :: (window: *NSWindow) {
    window_should_close = true;
}

// @TODO need to be able to accept options from the application layer
create_menu_bar :: () { 
    menu_bar := objc_init(objc_alloc(NSMenu));
    autorelease(menu_bar);
    
    setAppearance_sel := sel_registerName("setAppearance:");
    setAppearance_func :: #type (*void, Selector, *void) -> void #c_call;
    set_func := cast(setAppearance_func) objc_msgSend;
    set_func(menu_bar, setAppearance_sel, null);
    
    NSApp.setMainMenu(NSApp, menu_bar);
    
    S :: NSString.getTempString;
    
    app_menu_item := menu_bar.addItemWithTitle(menu_bar, S(""), null, S(""));
    autorelease(app_menu_item);
    
    app_menu := objc_init(objc_alloc(NSMenu));
    autorelease(app_menu);
    set_func(app_menu, setAppearance_sel, null);
    
    fullscreen_item := app_menu.addItemWithTitle(app_menu, S("Enter Full Screen"), 
                                                 selector("toggleFullScreen:"), S("f"));
    
    new_mask := NSEventModifierFlagControl | NSEventModifierFlagCommand;
    NSMenuItem.setKeyEquivalentModifierMask(fullscreen_item, new_mask);
    
    app_menu.addItemWithTitle(app_menu, S("Quit"), selector("terminate:"), S("q"));
    
    app_menu_item.setSubmenu(app_menu_item, app_menu);
    NSApplication.setAppleMenu(NSApp, app_menu);
}


platform_get_dpi_scale :: (window: Window_Type) -> float {
    if !window return 1.0;

    ns_window := cast(*NSWindow) window;

    // Get the backing scale factor for Retina displays
    // NSWindow inherits backingScaleFactor from NSView
    backing_scale := NSWindow.backingScaleFactor(ns_window);

    // Clamp to reasonable values
    if backing_scale < 1.0 backing_scale = 1.0;
    if backing_scale > 3.0 backing_scale = 3.0;

    return cast(float) backing_scale;
}

platform_shutdown :: () {
} 
