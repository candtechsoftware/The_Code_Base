
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
    size:     Vec2(float64);
    format:   Render_Texture_2D_Format;
    kind:     Render_Resource_Kind;
}

operator == :: (a: Render_Metal_Texure_2D, b: Render_Metal_Texure_2D) -> bool {
    return a.texture == b.texture && a.kind == b.kind; 
}


Render_Metal_Buffer :: struct {
    buffer: *void;
    size:   u64;
    kind:   Render_Resource_Kind;
}

operator == :: (a: Render_Metal_Buffer, b: Render_Metal_Buffer) -> bool {
    return a.buffer == b.buffer && a.kind == b.kind; 
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


    textures:           [..]*Render_Metal_Texure_2D;
    buffers:            [..]*Render_Metal_Buffer;
    window_equips:      [16]*Render_Metal_Window_Equip;  // Fixed-size array of pointers
    window_equip_count: u64;
    window_equip_cap    :u64= 16;
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
    case;
        assert(0 && "Unknown texture format");
        return .MTLPixelFormatRGBA8Unorm;
    }
}

render_metal_sample_channel_map_from_tex_2d_format :: (format: Render_Texture_2D_Format) -> Matrix4 {
    m := Matrix4_Identity;

    if format == {
        case .R8;  #through;
        case .R16; #through;
        case .R32;
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
    r_metal_state.font_sampler = MTLDevice.newSamplerStateWithDescriptor(r_metal_state.device, font_sample_desc);

    for 0..METAL_FRAMES_IN_FLIGHT-1 {
        r_metal_state.frames[it].semaphore = dispatch_semaphore_create(1);

        rect_buffer_size : u64 = 256 * 1024;
        r_metal_state.frames[it].rect_instance_buffer_size = rect_buffer_size;
        r_metal_state.frames[it].rect_instance_buffer = MTLDevice.newBufferWithLength_options(r_metal_state.device, rect_buffer_size, .MTLResourceStorageModeShared | .MTLResourceCPUCacheModeWriteCombined);
        assert(r_metal_state.frames[it].rect_instance_buffer != null);

        mesh_uniform_buffer_size : u64 = 16 * 1024;
        r_metal_state.frames[it].mesh_uniform_buffer = MTLDevice.newBufferWithLength_options(r_metal_state.device, mesh_uniform_buffer_size, .MTLResourceStorageModeShared | .MTLResourceCPUCacheModeWriteCombined);
        assert(r_metal_state.frames[it].mesh_uniform_buffer != null);


        for j: 0..METAL_BUFFER_POOL_SIZE-1 {
            r_metal_state.frames[it].buffer_pool[j].buffer = null;
            r_metal_state.frames[it].buffer_pool[j].size   = 0;
            r_metal_state.frames[it].buffer_pool[j].buffer = null;
        }

    }

    r_metal_state.current_frame_index = 0;

    rect_vertices :=  Vector2.[
        Vector2.{-1.0,  -1.0},
        Vector2.{1.0,   -1.0},
        Vector2.{-1.0,   1.0},
        Vector2.{1.0,    1.0},
    ];
    rect_vertices_size : u64 = size_of(Vector2) * rect_vertices.count;

    r_metal_state.rect_vertex_buffer = MTLDevice.newBufferWithBytes_length_options(r_metal_state.device, *rect_vertices, rect_vertices_size, .MTLResourceStorageModeManaged);
    MTLBuffer.didModifyRange(r_metal_state.rect_vertex_buffer, xx .{0, rect_vertices_size});

    r_metal_state.render_pass_ui_desc   = MTLRenderPassDescriptor.renderPassDescriptor();
    r_metal_state.render_pass_blur_desc = MTLRenderPassDescriptor.renderPassDescriptor();
    r_metal_state.render_pass_geo_desc  = MTLRenderPassDescriptor.renderPassDescriptor();

    // Initialize window equips array to null
    for 0..r_metal_state.window_equip_cap-1 {
        r_metal_state.window_equips[it] = null;
    }

    log("Metal renderer initialized successfully\n");
    log("Using % frames in flight with % maximum drawables", METAL_FRAMES_IN_FLIGHT, METAL_FRAMES_IN_FLIGHT);
    metal_initialized = true;

}

render_window_equip :: (handle: Platform_Handle) -> Render_Handle {
    window := platform_window_from_handle(handle);
    if window == null {
        return render_handle_zero();
    }

    scale := 2.0; // Default for retina display

    // Find free slot (like C version does)
    slot: u64 = 0;
    while slot < r_metal_state.window_equip_count {
        if !r_metal_state.window_equips[slot] {
            break;
        }
        slot += 1;
    }

    if slot >= r_metal_state.window_equip_cap {
        assert(false, "Too many window equips");
        return render_handle_zero();
    }

    // Update count if we're using a new slot
    if slot >= r_metal_state.window_equip_count {
        r_metal_state.window_equip_count = slot + 1;
    }

    equip := New(Render_Metal_Window_Equip);
    memset(equip, 0, size_of(Render_Metal_Window_Equip));

    layer := objc_init(objc_alloc(CAMetalLayer));
    CAMetalLayer.setDevice(layer, r_metal_state.device);
    CAMetalLayer.setPixelFormat(layer, .MTLPixelFormatBGRA8Unorm);
    CAMetalLayer.setFramebufferOnly(layer, YES);
    CAMetalLayer.setDisplaySyncEnabled(layer, NO);
    CAMetalLayer.setAllowsNextDrawableTimeout(layer, NO);
    CAMetalLayer.setPresentsWithTransaction(layer, NO);
    CAMetalLayer.setMaximumDrawableCount(layer, xx 3);
    CAMetalLayer.setWantsExtendedDynamicRangeContent(layer, NO);

    ns_window    := cast(*NSWindow) window;
    content_view := NSWindow.contentView(ns_window);

    setLayer_sel := sel_registerName("setLayer:");
    setLayer_func :: #type (*void, Selector, *void) -> void #c_call;
    set_layer := cast(setLayer_func) objc_msgSend;
    set_layer(content_view, setLayer_sel, layer);

    setContentsScale_sel := sel_registerName("setContentsScale:");
    setContentsScale_func :: #type (*void, Selector, CGFloat) -> void #c_call;
    set_scale := cast(setContentsScale_func) objc_msgSend;
    set_scale(layer, setContentsScale_sel, scale);

    frame := NSView.frame(content_view);
    equip.size = .{xx frame.size.width, xx frame.size.height};
    equip.scale = scale;
    drawable_size := NSMakeSize(frame.size.width * scale, frame.size.height * scale);
    CAMetalLayer.setDrawableSize(layer, drawable_size);

    descriptor_depth := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(.MTLPixelFormatDepth32Float, xx drawable_size.width, xx drawable_size.height, NO);
    MTLTextureDescriptor.setTextureType(descriptor_depth, .MTLTextureType2DMultisample);
    MTLTextureDescriptor.setSampleCount(descriptor_depth, 4);
    MTLTextureDescriptor.setUsage(descriptor_depth, .MTLTextureUsageRenderTarget);
    MTLTextureDescriptor.setStorageMode(descriptor_depth, .MTLStorageModePrivate);
    equip.depth_texture = xx MTLDevice.newTextureWithDescriptor(r_metal_state.device, descriptor_depth);

    equip.layer = layer;
    r_metal_state.window_equips[slot] = equip;

    result := render_handle_zero();
    result.kind = .METAL;
    result.mtl = cast(*void)(slot + 1);
    return result;
}

renderer_window_unequip :: (window: Platform_Handle, window_equip: Render_Handle) {
    if !r_metal_state || window_equip.kind != .METAL || !window_equip.mtl {
        return;
    }

    window_equip_slot := cast(u64)window_equip.mtl - 1;

    if window_equip_slot >= r_metal_state.window_equip_cap {
        log_error("Invalid window equipment slot %", window_equip_slot);
        return;
    }

    metal_window_equip := r_metal_state.window_equips[window_equip_slot];
    if !metal_window_equip {
        log_error("Window equipment slot % already released", window_equip_slot);
        return;
    }

    // Release Metal objects
    if metal_window_equip.depth_texture {
        // TODO: Proper Metal release
        metal_window_equip.depth_texture = null;
    }

    // Mark slot as free
    memset(metal_window_equip, 0, size_of(Render_Metal_Window_Equip));
    r_metal_state.window_equips[window_equip_slot] = null;
}


render_metal_texture_format_mul :: inline (format: Render_Texture_2D_Format) -> u32 {
    if format == {
            case .R8; return 1;

            case .RG8; #through;
            case .R16; return 2;

            case .RGBA8; #through;
            case .R32;   #through;
            case .BGRA8; return 4;
            case .RGBA16; return 8; 
    } 

    return 1;
} 

render_texture_2D_alloc :: (kind: Render_Resource_Kind, size: Vec2(float64), format: Render_Texture_2D_Format, data: *void) -> Render_Handle {
    alloc := Allocator.{flat_pool_allocator_proc, r_metal_state.pool}; 
    push_allocator(alloc);

    texture := array_add(*r_metal_state.textures); 
    memset(texture, 0, size_of(Render_Metal_Texure_2D));

    texture.*.size   = size;
    texture.*.format = format;
    texture.*.kind   = kind;


    desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        render_metal_pixel_format_from_tex_2d_format(format),
        xx size.x,
        xx size.y,
        NO, 
    );

    
    if kind == .DYNAMIC {
        MTLTextureDescriptor.setUsage(desc, .MTLTextureUsageShaderWrite);
    } else {
        MTLTextureDescriptor.setUsage(desc, .MTLTextureUsageShaderRead);
    }
    

    text_id := MTLDevice.newTextureWithDescriptor(r_metal_state.device, desc);
    texture.*.texture = text_id;

    bytes_per_row := xx size.x * render_metal_texture_format_mul(format);

    sample_desc := objc_init(objc_alloc(MTLSamplerDescriptor));
    MTLSamplerDescriptor.setMinFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    MTLSamplerDescriptor.setMagFilter(sample_desc, .MTLSamplerMinMagFilterLinear);
    MTLSamplerDescriptor.setSAddressMode(sample_desc, .MTLSamplerAddressModeClampToEdge);
    MTLSamplerDescriptor.setTAddressMode(sample_desc, .MTLSamplerAddressModeClampToEdge);

    texture.*.sampler = MTLDevice.newSamplerStateWithDescriptor(r_metal_state.device, sample_desc);

    handle := render_handle_zero();
    handle.kind = .METAL;
    handle.mtl = texture;

    return handle;
}


render_texture_2D_release :: (handle: Render_Handle) {
    if handle.mtl == null {
        log("texture is null could have already been released\n");
    }

    texture := render_metal_texture_find(handle);
    if !texture return;

    if texture.texture {
        release(texture.texture);
    }

    if texture.sampler {
        release(texture.sampler);
    }
}

render_buffer_alloc :: (kind: Render_Resource_Kind, size: u64, data: *void) -> Render_Handle {
    if !r_metal_state {
        return render_handle_zero();
    }

    slot: s64 = 0;
    while slot < xx r_metal_state.buffers.count {
        if !r_metal_state.buffers[slot].buffer {
            break;
        }
        slot += 1;
    }

    if slot >= r_metal_state.buffers.count {
        alloc := Allocator.{flat_pool_allocator_proc, r_metal_state.pool};
        push_allocator(alloc);
        array_add(*r_metal_state.buffers);
    }

    buf := r_metal_state.buffers[slot];
    memset(*buf, 0, size_of(Render_Metal_Buffer));

    buf.size = size;
    buf.kind = kind;

    options: MTLResourceOptions;
    if kind == .DYNAMIC {
        options = .MTLResourceStorageModeShared | .MTLResourceCPUCacheModeWriteCombined;
    } else {
        options = .MTLResourceStorageModeManaged;
    }

    if data {
        buf.buffer = MTLDevice.newBufferWithBytes_length_options(r_metal_state.device, data, size, options);

        if kind == .STATIC {
            MTLBuffer.didModifyRange(buf.buffer, xx .{0, size});
        }
    } else {
        buf.buffer = MTLDevice.newBufferWithLength_options(r_metal_state.device, size, options);
    }

    handle := render_handle_zero();
    handle.kind = .METAL;
    handle.mtl = buf;
    return handle;
}

render_buffer_release :: (handle: Render_Handle) {
    if !r_metal_state || handle.mtl == null {
        return;
    }

    buf := cast(*Render_Metal_Buffer) handle.mtl;
    found, idx := base_array_find(r_metal_state.buffers, buf);
    if !found {
        log("Buffer was not found\n");
        return;
    }

    if buf.buffer {
        release(buf.buffer);
    }

    memset(buf, 0, size_of(Render_Metal_Buffer));
}


// @Speed we can do better than a linear scan
render_metal_texture_find :: (handle: Render_Handle) -> *Render_Metal_Texure_2D {
    tex := cast(*Render_Metal_Texure_2D) handle.mtl;
    found, idx := base_array_find(r_metal_state.textures, tex); 
    if !found {
        log("Texture was not found\n");
        return null;
    } 
    return r_metal_state.textures[idx];
} 

render_kind_from_texture_2D :: (handle: Render_Handle) -> Render_Resource_Kind {
    if handle.mtl == null {
        return .STATIC;
    } 

    tex := render_metal_texture_find(handle);
    return ifx tex then tex.kind else .STATIC;
}


render_format_from_texture_2D :: (handle: Render_Handle) -> Render_Texture_2D_Format {
    if handle.mtl == null {
        return .RGBA8;
    }
    tex := render_metal_texture_find(handle);
    return ifx tex then tex.format else .RGBA8;
}


render_fill_texture_2D_region :: (handle: Render_Handle, sub_rect: Rng2, data: *void) {
    if data == null || handle.mtl == null return;

    tex := render_metal_texture_find(handle);

    if !tex.texture  return;

    bytes_per_row := cast(u64)(sub_rect.max.x - sub_rect.min.x) * xx render_metal_texture_format_mul(tex.format);

    region := MTLRegionMake2D(xx sub_rect.min.x, xx sub_rect.min.y, xx (sub_rect.max.x - sub_rect.min.x), xx (sub_rect.max.y - sub_rect.min.y));
    MTLTexture.replaceRegion_mipmapLevel_slice_withBytes_bytesPerRow_bytesPerImage(
        tex.texture,
        region,
        0,
        0,
        data,
        bytes_per_row,
        0);

}



// @TODO(Alex) we need to make this more general for the future to
// accept shaders at runtime and recompile
render_metal_init_shaders :: () {
    assert(r_metal_state != null);

    log("Starting Metal shader initialization\n");
    err := New(NSError);
    push_allocator(temp);
    {  // RECT SHADER
        // @TODO(Alex): this may not work in deployed version need to validate later
        shader_path  := tprint("%/shaders/metal/rect.metal", #filepath);
        data, file_ok := read_entire_file(shader_path);
        assert(file_ok, tprint("Failed to read file at %", shader_path));
        assert(data.count != 0);

        source_str := CFStringCreateWithCString(null, data.data, CFStringEncoding.UTF8);
        error: *NSError = null;
        rect_library := MTLDevice.newLibraryWithSource_options_error(r_metal_state.device, cast(*NSString) source_str, null, *error);
        CFRelease(source_str);
        assert(rect_library != null, "Failed to compile Metal shaders from source");
        vertex_function := MTLLibrary.newFunctionWithName(rect_library, cast(*NSString) cfstring_from_string("rect_vertex_main"));
        fragment_function := MTLLibrary.newFunctionWithName(rect_library, cast(*NSString) cfstring_from_string("rect_fragment_main"));
        assert(vertex_function && fragment_function, "Failed to find functions");
        pipeline_desc := cast(*MTLRenderPipelineDescriptor) objc_init(objc_alloc(objc_getClass("MTLRenderPipelineDescriptor")));
        MTLRenderPipelineDescriptor.setVertexFunction(pipeline_desc, vertex_function);
        MTLRenderPipelineDescriptor.setFragmentFunction(pipeline_desc, fragment_function);
        color_attachments := MTLRenderPipelineDescriptor.colorAttachments(pipeline_desc);
        color_attachment_0 := MTLRenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments,0);
        MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_0,                .MTLPixelFormatBGRA8Unorm);
        MTLRenderPipelineColorAttachmentDescriptor.setBlendingEnabled(color_attachment_0,            YES);
        MTLRenderPipelineColorAttachmentDescriptor.setRgbBlendOperation(color_attachment_0,          .MTLBlendOperationAdd);
        MTLRenderPipelineColorAttachmentDescriptor.setAlphaBlendOperation(color_attachment_0,        .MTLBlendOperationAdd);
        MTLRenderPipelineColorAttachmentDescriptor.setSourceRGBBlendFactor(color_attachment_0,       .MTLBlendFactorSourceAlpha);
        MTLRenderPipelineColorAttachmentDescriptor.setSourceAlphaBlendFactor(color_attachment_0,     .MTLBlendFactorOne);
        MTLRenderPipelineColorAttachmentDescriptor.setDestinationRGBBlendFactor(color_attachment_0,  .MTLBlendFactorOneMinusSourceAlpha);
        MTLRenderPipelineColorAttachmentDescriptor.setDestinationAlphaBlendFactor(color_attachment_0,  .MTLBlendFactorOneMinusSourceAlpha);
        MTLRenderPipelineDescriptor.setRasterSampleCount(pipeline_desc,  xx 4);
        r_metal_state.pipelines[Render_Metal_Shader_Kind.RECT].pipeline_state = MTLDevice.newRenderPipelineStateWithDescriptor_error(r_metal_state.device,pipeline_desc, *error);
        assert(!error, "Failed to get pipeline state");
        log("Created rect pipeline_state\n");

    }
    {  // BLUR SHADER
        shader_path  := tprint("%/shaders/metal/blur.metal", #filepath);
        data, file_ok := read_entire_file(shader_path);
        assert(file_ok, tprint("Failed to read file at %", shader_path));
        assert(data.count != 0);

        source_str := CFStringCreateWithCString(null, data.data, CFStringEncoding.UTF8);
        error: *NSError = null;
        rect_library := MTLDevice.newLibraryWithSource_options_error(r_metal_state.device, cast(*NSString) source_str, null, *error);
        CFRelease(source_str);
        assert(rect_library != null, "Failed to compile Metal shaders from source");
        vertex_function := MTLLibrary.newFunctionWithName(rect_library, cast(*NSString) cfstring_from_string("blur_vertex_main"));
        fragment_function := MTLLibrary.newFunctionWithName(rect_library, cast(*NSString) cfstring_from_string("blur_fragment_main"));
        assert(vertex_function && fragment_function, "Failed to find functions");


        pipeline_desc := cast(*MTLRenderPipelineDescriptor) objc_init(objc_alloc(objc_getClass("MTLRenderPipelineDescriptor")));
        MTLRenderPipelineDescriptor.setVertexFunction(pipeline_desc, vertex_function);
        MTLRenderPipelineDescriptor.setFragmentFunction(pipeline_desc, fragment_function);

        color_attachments := MTLRenderPipelineDescriptor.colorAttachments(pipeline_desc);
        color_attachment_0 := MTLRenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments,0);
        MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_0,                .MTLPixelFormatBGRA8Unorm);
        MTLRenderPipelineDescriptor.setRasterSampleCount(pipeline_desc,  xx 4);
        r_metal_state.pipelines[Render_Metal_Shader_Kind.BLUR].pipeline_state = MTLDevice.newRenderPipelineStateWithDescriptor_error(r_metal_state.device,pipeline_desc, *error);
        assert(!error, "Failed to get pipeline state");
        log("Created blur pipeline_state\n");

    }
    { // MESH SHADER
        // @TODO(Alex): this may not work in deployed version need to validate later
        shader_path  := tprint("%/shaders/metal/mesh.metal", #filepath);
        data, file_ok := read_entire_file(shader_path);
        assert(file_ok, tprint("Failed to read file at %", shader_path));
        assert(data.count != 0);

        source_str := CFStringCreateWithCString(null, data.data, CFStringEncoding.UTF8);
        error: *NSError = null;
        rect_library := MTLDevice.newLibraryWithSource_options_error(r_metal_state.device, cast(*NSString) source_str, null, *error);
        CFRelease(source_str);
        assert(rect_library != null, "Failed to compile Metal shaders from source");
        vertex_function := MTLLibrary.newFunctionWithName(rect_library, cast(*NSString) cfstring_from_string("mesh_vertex_main"));
        fragment_function := MTLLibrary.newFunctionWithName(rect_library, cast(*NSString) cfstring_from_string("mesh_fragment_main"));
        assert(vertex_function && fragment_function, "Failed to find functions");
        pipeline_desc := cast(*MTLRenderPipelineDescriptor) objc_init(objc_alloc(objc_getClass("MTLRenderPipelineDescriptor")));

        offset := 0;
        vertex_desc       := MTLRenderPipelineDescriptor.vertexDescriptor(pipeline_desc);
        vertex_attributes := MTLVertexDescriptor.attributes(vertex_desc);

        // Position
        vertex_attr_0 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(vertex_attributes, 0);
        MTLVertexAttributeDescriptor.setFormat(vertex_attr_0, .MTLVertexFormatFloat3);
        MTLVertexAttributeDescriptor.setOffset(vertex_attr_0, xx offset);
        MTLVertexAttributeDescriptor.setBufferIndex(vertex_attr_0, 0);
        offset += size_of(float) * 3;

        // Texcoord
        vertex_attr_1 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(vertex_attributes, 1);
        MTLVertexAttributeDescriptor.setFormat(vertex_attr_1, .MTLVertexFormatFloat2);
        MTLVertexAttributeDescriptor.setOffset(vertex_attr_1, xx offset);
        MTLVertexAttributeDescriptor.setBufferIndex(vertex_attr_1, 0);
        offset += size_of(float) * 2;

        // Normal
        vertex_attr_2 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(vertex_attributes, 2);
        MTLVertexAttributeDescriptor.setFormat(vertex_attr_2, .MTLVertexFormatFloat3);
        MTLVertexAttributeDescriptor.setOffset(vertex_attr_2, xx offset);
        MTLVertexAttributeDescriptor.setBufferIndex(vertex_attr_2, 0);
        offset += size_of(float) * 3;

        // Color
        vertex_attr_3 := MTLVertexAttributeDescriptorArray.objectAtIndexedSubscript(vertex_attributes, 3);
        MTLVertexAttributeDescriptor.setFormat(vertex_attr_3, .MTLVertexFormatFloat4);
        MTLVertexAttributeDescriptor.setOffset(vertex_attr_3, xx offset);
        MTLVertexAttributeDescriptor.setBufferIndex(vertex_attr_3, 0);
        offset += size_of(float) * 4;

        vertex_layouts := MTLVertexDescriptor.layouts(vertex_desc);
        vertex_layout_0 := MTLVertexBufferLayoutDescriptorArray.objectAtIndexedSubscript(vertex_layouts, 0);
        MTLVertexBufferLayoutDescriptor.setStride(vertex_layout_0, xx offset);
        MTLVertexBufferLayoutDescriptor.setStepRate(vertex_layout_0, xx 1);
        MTLVertexBufferLayoutDescriptor.setStepFunction(vertex_layout_0, .MTLVertexStepFunctionPerVertex);


        MTLRenderPipelineDescriptor.setVertexFunction(pipeline_desc, vertex_function);
        MTLRenderPipelineDescriptor.setFragmentFunction(pipeline_desc, fragment_function);

        color_attachments := MTLRenderPipelineDescriptor.colorAttachments(pipeline_desc);
        color_attachment_0 := MTLRenderPipelineColorAttachmentDescriptorArray.objectAtIndexedSubscript(color_attachments,0);
        MTLRenderPipelineColorAttachmentDescriptor.setPixelFormat(color_attachment_0,                .MTLPixelFormatBGRA8Unorm);
        MTLRenderPipelineDescriptor.setDepthAttachmentPixelFormat(pipeline_desc,                     .MTLPixelFormatDepth32Float);
        MTLRenderPipelineDescriptor.setRasterizationEnabled(pipeline_desc,                           YES);
        MTLRenderPipelineDescriptor.setRasterSampleCount(pipeline_desc,                              xx 4);
        r_metal_state.pipelines[Render_Metal_Shader_Kind.MESH].pipeline_state = MTLDevice.newRenderPipelineStateWithDescriptor_error(r_metal_state.device,pipeline_desc, *error);

        assert(!error, "Failed to get pipeline state");
        log("Created mesh pipeline_state\n");
    }

    reset_temporary_storage();
}


#import "Basic";
#import "Metal";
#import "macos";
#import "Objective_C";
#import "Objective_C/AppKit";
#import "Flat_Pool";
#import "Math";
#import "File";
