
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

    rect_instance_buffer:      *MTLBuffer;
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

    rect_vertex_buffer: *MTLBuffer; 

    blur_temp_texture:      *void;
    blur_temP_texture_size: Vector2; 
    blur_sampler:           id;
    font_sampler:           id;

    render_pass_ui_desc:    *MTLRenderPassDescriptor;
    render_pass_blur_desc:  *MTLRenderPassDescriptor;
    render_pass_geo_desc:   *MTLRenderPassDescriptor;


    textures:      [..]Render_Metal_Texure_2D; 
    buffers:       [..]Render_Metal_Buffer;
    widow_equiprs: [..]Render_Metal_Window_Equip; 
} 

r_metal_state: *Render_Metal_State; 
metal_initialized := false; 

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
    assert(!metal_initialized, "Metal is already initialized");

    init_metal();

    pool := New(Flat_Pool);
    alloc := Allocator.{flat_pool_allocator_proc, pool};
    push_allocator(alloc);

    r_metal_state        = New(Render_Metal_State);
    device              := cast(*MTLDevice)MTLCreateSystemDefaultDevice();
    r_metal_state.device = device;
    assert(r_metal_state.device != null);


    
    r_metal_state.command_queue = MTLDevice.newCommandQueue(r_metal_state.device);
    assert(r_metal_state.command_queue != null); 
    

    render_metal_init_shaders();

    sample_desc := objc_init(objc_alloc(MTLSamplerDescriptor));
    MTLSamplerDescriptor.setMinFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    MTLSamplerDescriptor.setMagFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    MTLSamplerDescriptor.setSAddressMode(sample_desc,.MTLSamplerAddressModeClampToEdge);
    MTLSamplerDescriptor.setTAddressMode(sample_desc,.MTLSamplerAddressModeClampToEdge);
    r_metal_state.blur_sampler = MTLDevice.newSamplerStateWithDescriptor(r_metal_state.device, sample_desc);


    font_sample_desc : *MTLSamplerDescriptor = objc_init(objc_alloc(MTLSamplerDescriptor));
    MTLSamplerDescriptor.setMinFilter(font_sample_desc, .MTLSamplerMinMagFilterLinear);
    MTLSamplerDescriptor.setMagFilter(font_sample_desc, .MTLSamplerMinMagFilterLinear);
    MTLSamplerDescriptor.setSAddressMode(font_sample_desc,   .MTLSamplerAddressModeClampToEdge);
    MTLSamplerDescriptor.setTAddressMode(font_sample_desc,   .MTLSamplerAddressModeClampToEdge);
    print("Hello 1 %  == %\n", font_sample_desc, r_metal_state.device);
    r_metal_state.font_sampler = MTLDevice.newSamplerStateWithDescriptor(r_metal_state.device, font_sample_desc);
    print("Hello 2 %  == %\n", r_metal_state, r_metal_state.device);

    for 0..METAL_FRAMES_IN_FLIGHT-1 {
        r_metal_state.frames[it].semaphore = dispatch_semaphore_create(1); 

        rect_buffer_size : u64 = 256 * 1024; 
        r_metal_state.frames[it].rect_instance_buffer_size = rect_buffer_size;
        r_metal_state.frames[it].rect_instance_buffer = r_metal_state.device.newBufferWithLength_options(r_metal_state.device, rect_buffer_size, .MTLResourceStorageModeShared | .MTLResourceCPUCacheModeWriteCombined);
        assert(r_metal_state.frames[it].rect_instance_buffer != null);

        mesh_uniform_buffer_size : u64 = 16 * 1024; 
        r_metal_state.frames[it].mesh_uniform_buffer = r_metal_state.device.newBufferWithLength_options(r_metal_state.device, mesh_uniform_buffer_size, .MTLResourceStorageModeShared | .MTLResourceCPUCacheModeWriteCombined);
        assert(r_metal_state.frames[it].mesh_uniform_buffer != null);


        for j: 0..METAL_BUFFER_POOL_SIZE-1 {
            r_metal_state.frames[it].buffer_pool[j].buffer = null;
            r_metal_state.frames[it].buffer_pool[j].size   = 0;
            r_metal_state.frames[it].buffer_pool[j].buffer = null;
        } 

    } 
    print("Hello 2 %  == %\n", r_metal_state, r_metal_state.device);

    r_metal_state.current_frame_index = 0; 

    rect_vertices :=  Vector2.[
        Vector2.{-1.0,  -1.0},
        Vector2.{1.0,   -1.0},
        Vector2.{-1.0,   1.0},
        Vector2.{1.0,    1.0},
    ];
    rect_vertices_size : u64 = size_of(Vector2) * rect_vertices.count;

    r_metal_state.rect_vertex_buffer = r_metal_state.device.newBufferWithBytes_length_options(r_metal_state.device, *rect_vertices, rect_vertices_size, .MTLResourceStorageModeManaged);
    r_metal_state.rect_vertex_buffer.didModifyRange(r_metal_state.rect_vertex_buffer, xx .{0 , rect_vertices_size});

    r_metal_state.render_pass_ui_desc   = MTLRenderPassDescriptor.renderPassDescriptor();
    r_metal_state.render_pass_blur_desc = MTLRenderPassDescriptor.renderPassDescriptor();
    r_metal_state.render_pass_geo_desc  = MTLRenderPassDescriptor.renderPassDescriptor();

    log("Metal renderer initialized successfully\n");
    log("Using % frames in flight with % maximum drawables", METAL_FRAMES_IN_FLIGHT, METAL_FRAMES_IN_FLIGHT);
    metal_initialized = true; 
}


render_metal_init_shaders :: () {
    assert(r_metal_state != null); 

    log("Starting Metal shader initialization\n");

    err := New(NSError); 
    push_allocator(temp);
    shader_path  := #filepath; 
    print("shader_path %\n", shader_path); 



}


#import "Basic";
#import "Metal";
#import "Objective_C";
#import "macos";
#import "Flat_Pool";
#import "Math";

