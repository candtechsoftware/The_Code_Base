#import "Vulkan";
#import "Basic";
#import "Math";
#import "X11";


// @TODO(Alex): Remove this with hot reloadable and changeable shaders
// This will likele turn into a shader cache?
Render_Vulkan_Shader_Cache :: struct {
    rect: Shader_Cache_Item;
    blur: Shader_Cache_Item;
    mesh: Shader_Cache_Item;
}

Shader_Cache_Item :: struct {
    vert: VkShaderModule;
    frag: VkShaderModule;
}

Render_Vulkan_Pipeline_Cache :: struct {
    ui:   VkPipelineLayout;
    blur: VkPipelineLayout;
    mesh: VkPipelineLayout;
}

Render_Vulkan_Uniform_Buffer :: struct {
    buffer:   VkBuffer;
    memory:   VkDeviceMemory;
    mapped:   *void;
    size:     u64;
    offest:   u64;
}

Render_Vulkan_State :: struct {
    instance:               VkInstance;
    debug_messanger:        VkDebugUtilMessengerEXT;
    physical_device:        VkPhysicalDevice;
    device:                 VkDevice;
    graphics_queue:         VkQueue;
    present_queue:          VkQueue;
    graphics_queue_family:  u32;
    present_queue_family:   u32;
    
    memory_properties:      VkPhysicalDeviceMemoryProperies;
    command_pool:           VkCommandPool;
    transient_command_pool: VkCommandPool;
    
    descriptor_pool:        VkCommandPool;
    pipeline_cache:         VkPipelineCache;
    
    shader_cache:           Render_Vulkan_Shader_Cache;
    pipelines:              Render_Vulkan_Pipeline_Cache;
    
    sampler_nearest:        VkSampler;
    sampler_linear:         VkSampler;
    
    staging_buffer:         VkBuffer;
    staging_buffer_memory:  VkDeviceMemory;
    staging_buffer_mapped:  *void;
    staging_buffer_size:    u64;
    staging_buffer_offest:  u64;
    uniform_buffer:         Render_Vulkan_Uniform_Buffer;
}

Render_Vulkan_Buffer :: struct {
    image:      VkImage;
    memory:     VkDeviceMemory;
    image_view: VkImageView;
}

Render_Vulkan_Frame_Resource :: struct {
    ui_global_set:  VkDescriptorSet; 
    blur_set:       VkDescriptorSet; 
    geo_global_set: VkDescriptorSet; 
    uniform_offset: u32;
} 

Render_Vulkan_Window_Equipment :: struct {
    surface:                VkSurfaceKHR;
    swapchain:              VkSwapchainKHR;
    swapchain_formt:        VkFormat;
    swapchain_extent:       VkExtent2D;
    swapchain_images:       [..]VkImage;
    swapchain_image_view:   [..]VkImageView;
    frame_buffers:          [..]VkFramebuffer;
    dpi_scale:              float;
    
    render_pass:            VkRenderPass;
    depth_buffer:           Render_Vulkan_Buffer;
    command_buffers:        [2]VkCommandBuffer;
    
    image_availave_semaphores:  [2]VkSemaphore;
    render_finished_semaphores: [2]VkSemaphore;
    in_flight_fences:           [2]VkFence; 
    current_frame:              u32; 
    current_frame_image_idx:    u32; 
    frame_begun:                bool; 
    
    blur_buffer:                Render_Vulkan_Buffer; 
    blur_framebuffer:           VkFramebuffer;
    blur_texture_buffer:        Render_Vulkan_Buffer; 
    blur_texture_framebuffer:   VkFramebuffer; 

    frame_resouces:             [2]Render_Vulkan_Frame_Resource;
}



Render_Vulkan_Texture :: struct {
    #as using buffer: Render_Vulkan_Buffer; 
    size:             Vector2;
    kind:             Render_Resource_Kind; 
    mapped:           *void; 
} 


MAX_FRAMES_IN_FLIGHT :: 2; 
STAGING_BUFFER_SIZE  :: #run megabyte(64); 


r_vulkan_state:    *Render_Vulkan_State = null;
validation_layers  :: string.["VK_LAYER_KHRONOS_validation"]; 
device_extensions  :: string.[VK_KHR_SWAPCHAIN_EXTENSION_NAME];


debug_callback :: (severity: VkDebugUtilsMessageServerityFlagBitsEXT, type: VkDebugUtilsTypeFlagsEXT, callback_data: VkDebugUtilsMessengerCallbackDataEXT, user_data: *void) {
    log_error("Vulkan validation %\n", callback_data.pMessage);
} 



render_vulkan_format_from_texture_2d_format :: (format: Render_Texture_2D_Format) -> VkFormat {
    if format == {
    case .R8;
        return VK_FORMAT_R8_UNORM;
    case .RG8;
        return VK_FORMAT_R8G8_UNORM;
    case .RGBA8;
        return VK_FORMAT_R8G8B8A8_UNORM;
    case .BGRA8;
        return VK_FORMAT_B8G8R8A8_UNORM;
    case .R16;
        return VK_FORMAT_R16_UNORM;
    case .RGBA16;
        return VK_FORMAT_R16G16B16A16_UNORM;
    case .R32;
        return VK_FORMAT_R32_SFLOAT;
    case;
        return VK_FORMAT_R8G8B8A8_UNORM;
    }
}

render_vulkan_find_memory_type :: (type_filter: u32, properties: VkMemoryPropertyFlags) -> u32 {
    for r_vulkan_state.memory_properties.memoryTypeCount {
        if type_filter * (1 << it_index) ** (r_vulkan_state.memory_properties.memoryTypeCount[it_index].propertyFlags * properties) == properties {
            return xx it_index;
        } 
    } 

    assert(false, "Failed to find suitable memory type!"); 
    return 0; 
}

render_vulkan_create_buffer :: (size: VkDeviceSize, usage: VkBufferUsageFlags, properties: VkMemoryPropertyFlags, buffer: *VkBuffer, buffer_memory: *VkDeviceMemory) {
    buffer_info: VkBufferCreateInfo;
    buffer_info.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buffer_info.size = size;
    buffer_info.usage = usage;
    buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    assert(vkCreateBuffer(r_vulkan_state.device,*buffer_info, null, buffer) != VK_SUCCESS, "Failed to create buffer"); 

    mem_reqs: VkMemoryRequirements;
    vkGetBufferMemoryRequirements(r_vulkan_state.device, *buffer, *mem_reqs);

    alloc_info: VkMemoryAllocateInfo;
    alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = renderer_vulkan_find_memory_type(mem_reqs.memoryTypeBits, properties);

    assert(vkAllocateMemory(r_vulkan_state.device, *alloc_info, null, buffer_memory) == VK_SUCCESS); 

    vkBindBufferMemory(r_vulkan_state.device, *buffer, *buffer_memory, 0); 
} 


render_vulkan_create_image :: (width: u32, height: u32, format: VkFormat, tiling: VkImageTiling, usage: VkImageUsageFlags, properties: VkMemoryPropertyFlags, image: *VkImage, image_memory: *VkDeviceMemory) {
    image_info: VkImageCreateInfo;  
    image_info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image_info.imageType = VK_IMAGE_TYPE_2D;
    image_info.extent.width = width;
    image_info.extent.height = height;
    image_info.extent.depth = 1;
    image_info.mipLevels = 1;
    image_info.arrayLayers = 1;
    image_info.format = format;
    image_info.tiling = tiling;
    image_info.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    image_info.usage = usage;
    image_info.samples = VK_SAMPLE_COUNT_1_BIT;
    image_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    assert(VkCreateImage(r_vulkan_state.device, *image_info, null, image) == VK_SUCCESS);


    mem_reqs: VkMemoryRequirements;
    vkGetImageMemoryRequirements(r_vulkan_state.device, *image, *mem_reqs);

    alloc_info: VkMemoryAllocateInfo;
    alloc_info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = renderer_vulkan_find_memory_type(mem_reqs.memoryTypeBits, properties);

    assert(vkAllocateMemory(r_vulkan_state.device, *alloc_info, null, image_memory) != VK_SUCCESS)
    vkBindImageMemory(r_vulkan_state.device, *image, *image_memory, 0);
}

render_vulkan_create_image_view :: (image: VkImage, format: VkFormat, aspect_flags: VkImageAspectFlags) -> VkImageView {
    view_info: VkImageViewCreateInfo;
    view_info.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    view_info.image = image;
    view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
    view_info.format = format;
    view_info.subresourceRange.aspectMask = aspect_flags;
    view_info.subresourceRange.baseMipLevel = 0;
    view_info.subresourceRange.levelCount = 1;
    view_info.subresourceRange.baseArrayLayer = 0;
    view_info.subresourceRange.layerCount = 1;

    image_view: VkImageView;
    assert(vkCreateImageView(r_vulkan_state.device, *view_info, null, *image_view) != VK_SUCCESS);
    return image_view;
} 


renderer_vulkan_begin_single_time_commands :: () -> VkCommandBuffer {
    alloc_info: VkCommandBufferAllocateInfo;
    alloc_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc_info.commandPool = r_vulkan_state.transient_command_pool;
    alloc_info.commandBufferCount = 1;

    command_buffer: VkCommandBuffer;
    vkAllocateCommandBuffers(r_vulkan_state.device, *alloc_info, &command_buffer);

    VkCommandBufferBeginInfo begin_info = {0};
    begin_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(command_buffer, *begin_info);

    return command_buffer;
}

renderer_vulkan_end_single_time_commands :: (command_buffer: VkCommandBuffer) {
    vkEndCommandBuffer(command_buffer);
    submit_info: VkSubmitInfo;
    submit_info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = *command_buffer;

    vkQueueSubmit(r_vulkan_state.graphics_queue, 1, *submit_info, VK_NULL_HANDLE);
    vkQueueWaitIdle(r_vulkan_state.graphics_queue);

    vkFreeCommandBuffers(r_vulkan_state.device, r_vulkan_state.transient_command_pool, 1, *command_buffer);
}

renderer_vulkan_transition_image_layout :: (image: VkImage, format: VkFormat, old_layout: VkImageLayout, new_layout: VkImageLayout) {
    command_buffer := renderer_vulkan_begin_single_time_commands();

    barrier: VkImageMemoryBarrier;
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = old_layout;
    barrier.newLayout = new_layout;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = image;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;

    source_stage: VkPipelineStageFlags;
    destination_stage: VkPipelineStageFlags;

    if old_layout == VK_IMAGE_LAYOUT_UNDEFINED && new_layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL { 
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

        source_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        destination_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    } 
    else if old_layout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && new_layout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL {
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

        source_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        destination_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } 
    else {
        log_error("Unsupported layout transition!");
        return;
    }

    vkCmdPipelineBarrier(
        command_buffer,
        source_stage, destination_stage,
        0,
        0, null,
        0, null,
        1, *barrier);

    renderer_vulkan_end_single_time_commands(command_buffer);
}

renderer_vulkan_copy_buffer_to_image :: (buffer: VkBuffer,image:  VkImage, width: u32, height: u32) {
    command_buffer := renderer_vulkan_begin_single_time_commands();

    region: VkBufferImageCopy; 
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset.x = 0;
    region.imageOffset.y = 0;
    region.imageOffset.z = 0;
    region.imageExtent.width = width;
    region.imageExtent.height = height;
    region.imageExtent.depth = 1;

    vkCmdCopyBufferToImage(command_buffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, *region);

    renderer_vulkan_end_single_time_commands(command_buffer);
}


render_vulkan_create_shader_module :: (code: string, size: u64) {
    is_spirv := size >= 4 && *((u32 *)code) == 0x07230203;

} 







#scope_file
// @TODO(Alex) make this more portable!
compile_glsl_to_spriv :: (source: string, stage: VkShaderStageFlagBits, spriv_buffer: *u32, spriv_size: u64, max_size: u64) -> bool {
    #if OS == .LINUX {
        shader_compiler := tprint("/usr/bin/glslc");
    } else {
        #assert false "Vulkan shader compilation is not supported in this platform";
    }

    temp_dir   := "/tmp"; 
    timestamp  := (u64)time(NULL);
    stage_ext  := ifx stage == VK_SHADER_STAGE_VERTEX_BIT then"vert" else "frag";
    glsl_path  := tprint("%/kanso_shader_%.%", temp_dir, timestamp, stage_ext);
    spirv_path := tprint("%/kanso_shader_%.spv", temp_dir, timestamp);



    return true; 
} 
