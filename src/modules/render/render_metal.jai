
#scope_file

METAL_FRAMES_IN_FLIGHT          :: 2;
METAL_BUFFER_POOL_SIZE          :: 256;
METAL_BUFFER_POOL_MIN_SIZE      :: (16 * 1024);
METAL_BUFFER_POOL_GROWTH_FACTOR :: 2;
Render_Metal_Shader_Kind :: enum {
    RECT; 
    BLUR; 
    MESH; 
} 

Render_Metal_Shader_Kind_COUNT :: #run enum_highest_value(Render_Metal_Shader_Kind) + 1;

Render_Metal_Texure_2D :: struct {
    texture: *void;
    sampler: *void; 
    size:     Vector2; 
    format:   Render_Texture_2D_Format; 
    kind:     Render_Resource_Kind; 
} 

Render_Metal_Buffer :: struct {
    buffer: *void;
    size:   u64; 
    kind:   Render_Resource_Kind; 
} 

Render_Metal_Window_Equip :: struct {
    layer:          CAMetalLayer; 
    depth_texture: *void; 
    size:           Vector2; 
    scale:          float;
} 

Render_Metal_Pipeline :: struct {
    pipeline_state:      *void; 
    depth_stencil_state: *void;
} 

Render_Metal_Buffer_Pool_Entry :: struct {
    buffer:      *void; 
    size:         u64;
    used_size:    u64; 
    in_use:       bool;
    reuse_count:  u32;
} 

Render_Metal_Frame_Data :: struct {
    semaphore:       *void; 
    command_buffer:  *void;

    rect_instance_buffer:      *void;
    rect_instance_buffer_size: u64; 
    rect_instance_buffer_used: u64;

mesh_uniform_buffer:      *void; 
    mesh_uniform_buffer_used: u64;

    buffer_pool:            [METAL_BUFFER_POOL_SIZE]Render_Metal_Buffer_Pool_Entry;
    buffer_pool_hit_count:  u32;
    buffer_pool_miss_count: u32; 
} 

Render_Metal_State :: struct {
    pool:                *Flat_Pool; 
    device:              *MTLDevice;
    command_queue:       *MTLCommandQueue;
    pipelines:           [Render_Metal_Shader_Kind_COUNT]Render_Metal_Pipeline; 
    frames:              [METAL_FRAMES_IN_FLIGHT]Render_Metal_Frame_Data;
    current_frame_index: u32; 

    rect_vertex_buffer: *void; 

    blur_temp_texture:      *void;
    blur_temP_texture_size: Vector2; 
    blur_sampler:           id;
    font_sampler:           id;

    render_pass_ui_desc:    *void;
    render_pass_blur_desc:    *void;
    render_pass_geo_desc:    *void;


    textures:      [..]Render_Metal_Texure_2D; 
    buffers:       [..]Render_Metal_Buffer;
    widow_equiprs: [..]Render_Metal_Window_Equip; 
} 

r_metal_state: *Render_Metal_State; 

render_metal_pixel_format_from_tex_2d_format :: (format: Render_Texture_2D_Format) -> MTLPixelFormat {
    if format == {
    case .R8;
        return .MTLPixelFormatR8Unorm;
    case .RG8;
        return .MTLPixelFormatRG8Unorm;
    case .RGBA8;
        return .MTLPixelFormatRGBA8Unorm;
    case .BGRA8;
        return .MTLPixelFormatBGRA8Unorm;
    case .R16;
        return .MTLPixelFormatR16Unorm;
    case .RGBA16;
        return .MTLPixelFormatRGBA16Unorm;
    case .R32;
        return .MTLPixelFormatR32Float;
    default:
        assert(0 && "Unknown texture format");
        return .MTLPixelFormatRGBA8Unorm;
    }
} 

render_metal_sample_channel_map_from_tex_2d_format :: (format: Render_Texture_2D_Format) -> Matrix4 {
    m := Matrix4_Identity;

    if format == {
         case; .R8;  #through;
         case; .R16; #through; 
         case; .R32;
             m.coef[0][0] = 1.0;
             m.coef[0][1] = 1.0;
             m.coef[0][2] = 1.0;
             m.coef[0][3] = 0.0;
             m.coef[1][3] = 0.0;
             m.coef[2][3] = 0.0;
             m.coef[3][0] = 0.0;
             m.coef[3][1] = 0.0;
             m.coef[3][2] = 0.0;
             m.coef[3][3] = 1.0;
         case .RG8;
             m.coef[0][0] = 1.0;
             m.coef[1][1] = 1.0;
             m.coef[2][0] = 0.0;
             m.coef[2][1] = 0.0;
             m.coef[2][2] = 0.0;
             m.coef[2][3] = 0.0;
             m.coef[3][0] = 0.0;
             m.coef[3][1] = 0.0;
             m.coef[3][2] = 0.0;
             m.coef[3][3] = 1.0;
    } 
    return m;
} 

#scope_export

render_init :: () {
    assert(r_metal_state != null, "Metal Render was already initialized\n");

    pool := New(Flat_Pool); 
    alloc := Allocator.{flat_pool_allocator_proc, pool};
    push_allocator(alloc);

    r_metal_state        = New(Render_Metal_State);
    r_metal_state.device = cast(*MTLDevice)MTLCreateSystemDefaultDevice();
    assert(r_metal_state.device != null); 
    r_metal_state.command_queue =  r_metal_state.device.newCommandQueue();
    assert(r_metal_state.command_queue != null); 
    

    render_metal_init_shaders(); // @TODO need to implement; 

    sample_desc : *MTLSamplerDescriptor = New(MTLSamplerDescriptor);
    sample_desc.setMinFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    sample_desc.setMagFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    sample_desc.setSAddressMode(sample_desc,.MTLSamplerAddressModeClampToEdge);
    sample_desc.setTAddressMode(sample_desc,.MTLSamplerAddressModeClampToEdge);
    r_metal_state.blur_sampler = r_metal_state.device.newSamplerStateWithDescriptor(r_metal_state.device, sample_desc);


    font_sample_desc : *MTLSamplerDescriptor = New(MTLSamplerDescriptor);
    font_sample_desc.setMinFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    font_sample_desc.setMagFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    font_sample_desc.setSAddressMode(sample_desc,.MTLSamplerAddressModeClampToEdge);
    font_sample_desc.setTAddressMode(sample_desc,.MTLSamplerAddressModeClampToEdge);
    r_metal_state.font_sampler = r_metal_state.device.newSamplerStateWithDescriptor(r_metal_state.device, font_sample_desc);


}




#import "Basic";
#import "Metal";
#import "Objective_C";
#import "Flat_Pool";
#import "Math";

