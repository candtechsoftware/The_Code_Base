#if OS :::: {
    case .LINUX; #load "render_vulkan.jai";
    case .MACOS; #load "render_metal.jai";
}

Render_Geo_Vertex_Flags :: enum_flags u32  {
    TEXCOORD :: (1<<0);
    NORMALS  :: (1<<1);
    RGB      :: (1<<2);
    RGBA     :: (1<<3);
};

Render_Geo_Topology_Kind :: enum  {
    R_GeoTopologyKind_Lines;
    R_GEOTOPOLOGYKIND_LINESTRIP;
    R_GEOTOPOLOGYKIND_TRIANGLES;
    R_GEOTOPOLOGYKIND_TRIANGLESTRIP;
}

RENDER_GEO_TOPOLOGY_KIND_COUNT :: #run enum_highest_value(RENDER_GEO_TOPOLOGY_KIND) + 1;

Render_Handle :: union {
    u64s: [1]u64; 
    u32s: [2]u32;
    u16s: [3]u16;
} 

Render_Rect_2D_Instance :: struct {
    dst:              Rng2; 
    src:              Rng2; 
    colors:           [CORNER_COUNT]Vector4; 
    corner_radii:     [CORNER_COUNT]Vector4; 
    border_thickness: float; 
    edge_softness:    float;
    white_texture:    float;
    _unused_:         [1]float;
} 

Render_Mesh_3D_Instance :: struct {
    xform: Matrix4; 
} 

Render_Batch :: struct {
    v: []u8; 
    byte_count: u64; 
    byte_cap:   u64; 
} 

Render_Batch_Node :: struct {
    next: *Render_Batch_Node; 
    v:    Render_Batch; 
} 

Render_Batch_List :: struct {
    allocator:    Allocator;
    first:        *Render_Batch_Node;
    last:         *Render_Batch_Node;

    batch_count:        u64; 
    byte_count:         u64;
    bytes_per_instance: u64; 
} 


Render_Texture_2D_Sample_Kind :: enum {
    NEAREST; 
    LINEAR;
} 
RENDER_TEXTURE_2D_SAMPLE_KIND_COUNT :: #run enum_highest_value(Render_Texture_2D_Sample_Kind) + 1;

Render_Texture_2D_Format :: enum  {
   R8;
   RG8; 
   RGBA8;
   BGRA8;
   R16;
   RGBA16;
   R32;
   RG32;
   RGBA32;
}
RENDER_TEXTURE_2D_FORMAT_COUNT :: #run enum_highest_value(Render_Texture_2D_Format) + 1;

Render_Batch_Group_2D_Params :: struct {
    texture:          Render_Handle;
    tex_sample_kind:  Render_Texture_2D_Sample_Kind;
    xform:            Matrix3; 
    clip:             Rng2; 
    transparency:     float;
} 


Render_Batch_Group_2D_Node :: struct {
    next:    *Render_Batch_Group_2D_Node; 
    batches: Render_Batch_List; 
    params:  Render_Batch_Group_2D_Params; 
} 

Render_Batch_Group_2D_List :: struct {
    first: *Render_Batch_Group_2D_Node;
    last:  *Render_Batch_Group_2D_Node;
    count: u64;
} 


Render_Batch_Group_3D_Params :: struct {
    mesh_vertices:          Render_Handle; 
    mesh_indices:           Render_Handle; 
    mesh_geo_topology:      Render_Geo_Topology_Kind; 
    mesh_goe_vertex_flags:  Render_Geo_Vertex_Flags; 
    albedo_tex_sample_kind: Render_Texture_2D_Sample_Kind; 
    xform:                  Matrix4;
} 

Render_Batch_Group_3D_Map_Node :: struct {
    next:     *Render_Batch_Group_3D_Map_Node;  
    hash:     u64;
    batches:  Render_Batch_List; 
    params:   Render_Batch_Group_3D_Params; 
}

Render_Batch_Group_3D_Map :: struct {
    slots: [..]*Render_Batch_Group_3D_Map_Node; 
} 

Render_Pass_Kind :: enum {
    UI; 
    BLUR; 
    GEO3D;
}

Render_Pass :: struct {
    kind: Render_Pass_Kind; 
} 


Render_Pass_UI_Params :: struct {
    rects: Render_Batch_Group_2D_List; 
} 

Render_Pass_Blur_Params :: struct {
    rect:         Rng2;
    clip:         Rng2; 
    blur_size:    float;
    corner_radii: [CORNER_COUNT]float; 
} 

Render_Pass_Geo_Params :: struct {
    viewport:     Rng2;
    clip:         Rng2;
    view:         Matrix4; 
    projection:   Matrix4; 
    mesh_batches: Render_Batch_Group_3D_Map; 
} 

Render_Pass_UI :: struct {
    #as using pass: Render_Pass;
    params: *Render_Pass_UI_Params;
} 

Render_Pass_Blur :: struct {
    #as using pass: Render_Pass;
    params: *Render_Pass_Blur_Params;
}

Render_Pass_Geo :: struct {
    #as using pass: Render_Pass;
    params: *Render_Pass_Geo_Params;
}

Render_Pass_Node :: struct {
    next: *Render_Pass_Node; 
    val:  Render_Pass;
} 

Render_Pass_List :: struct {
    first: *Render_Pass_Node; 
    last:  *Render_Pass_Node;
    count: u64; 
} 

render_sample_channel_map_from_texture :: (fmt: Render_Texture_2D_Format) -> Matrix4 {
    res := Matrix4_Identity();
    if fmt == {
    case .R8; {
            res.v[0] = .{1, 1, 1, 1}; 
        } 
    case; 
    } 
} 

render_handle_zero :: () -> Render_Handle {
    r: Render_Handle; 
    return r;
} 

operator == :: (a: *Render_Handle, b: *Render_Handle) {
    return memcmp(a, b, size_of(Render_Handle)) == 0; 
} 

render_batch_list_create :: (instance_size: u64) -> Render_Batch_List {
    r: Render_Batch_List;
    list.bytes_per_instance = instance_size; 
    pool                    := New(Flat_Pool);  // @TODO: should create own arena
    list.allocator:         = Allocator.{flat_pool_allocator_proc, pool};
    return list; 
} 

render_batch_list_push :: (list: *Render_Batch_List, batch_instance_cap: u64) -> void *{
    push_allocator(list.allocator);
    instance : *void = null;
    {
        n := list.last;
        if n == null || n.v.byte_count + list.bytes_per_instance > n.v.byte_cap {
            n = New(Render_Batch_Node);
            n.v.byte_cap = batch_instance_cap * list.bytes_per_instance; 
            n.v.v = NewArray(n.v.byte_cap, u8);
            SLL_QUEUE_PUSH(list.first, list.last, n); 
            list.batch_count += 1; 
        }    
        instance = n.v.v + n.v.byte_count; 
        n.v
    } 
    return instance;
} 




#import "Math";
#import "Basic"; 
#import "Flat_Pool";
