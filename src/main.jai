#import "Basic"; 
#load "./modules/module.jai"; 


App_State :: struct {
    running: bool = true; 
} 

app_state: *App_State = null;



main :: () {
    window, window_ok := platform_create_window(800, 880, "Demo");
    if !window_ok {
        log_error("Failed to create window\n");
        return;
    }

    app_state = New(App_State);

    // Initialize the Metal renderer before equipping the window
    render_init();

    window_equip := render_window_equip(window);


    while app_state.running {
        reset_temporary_storage();
        platform_process_events_this_frame(); 
        handle_input(); 


        if platform_window_should_close() {
            app_state.running = false; 
        } 
    } 
} 


handle_input :: () {
    for platform_events_this_frame {
        if it.type == .KEYBOARD {
            if it.key_pressed && it.key_code == .ESCAPE {
                app_state.running = false;
            }
        } else if it.type == .QUIT {
            app_state.running = false;
        }
    }
} 
