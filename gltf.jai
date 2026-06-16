/*

glTF 2.0 Loader

Reference: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html

glTF is a JSON-based format from Khronos. Unlike OBJ which is line-based plaintext,
glTF uses JSON to describe a scene graph with typed accessors into binary buffer data.

The basic structure:
  - Buffers:      Raw binary blobs (usually .bin files)
  - BufferViews:  Slices into buffers (offset + length + optional stride)
  - Accessors:    Typed views into bufferViews (component type, element type, count)
  - Meshes:       Collections of primitives
  - Primitives:   Geometry with attribute accessors + optional index accessor + material
  - Materials:    PBR metallic-roughness based material descriptions
  - Textures:     Reference an image + sampler
  - Images:       File path or embedded data for texture images
  - Samplers:     Texture filtering/wrapping parameters
  - Nodes:        Scene graph nodes with transforms, referencing meshes/children
  - Scenes:       Collections of root nodes

We support:
  - External .bin buffer files
  - Meshes with POSITION, NORMAL, TEXCOORD_0..N attributes
  - Multiple UV channels (TEXCOORD_0, TEXCOORD_1, TEXCOORD_2, ...)
  - Indexed and non-indexed geometry
  - PBR metallic-roughness materials (base color, metallic, roughness, emissive, normal map)
  - Texture info texcoord index selects which UV channel to use
  - Node hierarchy with TRS transforms and matrix transforms
  - Multiple scenes

We do NOT support (yet):
  - .glb binary container format
  - Data URIs (embedded base64 buffers/images)
  - Morph targets
  - Skinning / animations (want this soon)
  - Extensions
  - Sparse accessors
  - Vertex colors

*/



#import "tbx/json";

// enums

Gltf_Component_Type :: enum u32 {
    BYTE            :: 5120;
    UNSIGNED_BYTE   :: 5121;
    SHORT           :: 5122;
    UNSIGNED_SHORT  :: 5123;
    UNSIGNED_INT    :: 5125;
    FLOAT           :: 5126;
}

Gltf_Accessor_Type :: enum {
    SCALAR;
    VEC2;
    VEC3;
    VEC4;
    MAT2;
    MAT3;
    MAT4;
}

Gltf_Primitive_Mode :: enum u32 {
    POINTS          :: 0;
    LINES           :: 1;
    LINE_LOOP       :: 2;
    LINE_STRIP      :: 3;
    TRIANGLES       :: 4;
    TRIANGLE_STRIP  :: 5;
    TRIANGLE_FAN    :: 6;
}

Gltf_Texture_Wrap :: enum u32 {
    CLAMP_TO_EDGE   :: 33071;
    MIRRORED_REPEAT :: 33648;
    REPEAT          :: 10497;
}

Gltf_Texture_Filter :: enum u32 {
    NEAREST                 :: 9728;
    LINEAR                  :: 9729;
    NEAREST_MIPMAP_NEAREST  :: 9984;
    LINEAR_MIPMAP_NEAREST   :: 9985;
    NEAREST_MIPMAP_LINEAR   :: 9986;
    LINEAR_MIPMAP_LINEAR    :: 9987;
}

Gltf_Alpha_Mode :: enum {
    OPAQUE; // ignore alpha, surface is fully solid
    MASK;   // binary transparency, pixel value is either full opaque or full solid (eg grass)
    BLEND;  // continuous transparncy, pixel values need to blend with what's behind them
}

Gltf_Light_Type :: enum {
    POINT;
    SPOT;
    DIRECTIONAL;
}

Gltf_Animation_Path :: enum {
    TRANSLATION;
    ROTATION;
    SCALE;
    WEIGHTS;  // morph targets — we won't use this yet
}

Gltf_Interpolation :: enum {
    LINEAR;
    STEP;
    CUBICSPLINE;
}



// data structures

/*
a uniform resource identifier (uri) is like a generalized file path, it can be:
- a literal file path on your local machine
- a url to a file
- TODO fill this in.
*/

Gltf_Buffer :: struct {
    uri         : string; // most often this points to something like model.bin or something
    byte_length : int; // advertised_byte_length
    loaded_data : string;  // bytes_weve_loaded, can be used to verify that you got everything.
}

Gltf_Buffer_View :: struct {
    buffer_index : int;
    byte_offset  : int;
    byte_length  : int;
    byte_stride  : int;   // 0 means tightly packed
}

Gltf_Accessor :: struct {
    buffer_view_index : int = -1;
    byte_offset       : int;
    component_type    : Gltf_Component_Type = .FLOAT;
    accessor_type     : Gltf_Accessor_Type  = .SCALAR;
    count             : int;
    normalized        : bool;
}

MAX_TEXCOORD_CHANNELS :: 8;  // glTF spec doesn't define a hard limit; 8 is generous

Gltf_Primitive :: struct {
    position_accessor   : int = -1;
    normal_accessor     : int = -1;
    tangent_accessor    : int = -1;

    texcoord_accessors  : [..] int;   // indexed by channel: [0] = TEXCOORD_0, [1] = TEXCOORD_1, ...

    joints_accessors  : [..] int;   // JOINTS_0, JOINTS_1, ...
    weights_accessors : [..] int;   // WEIGHTS_0, WEIGHTS_1, ...

    indices_accessor    : int = -1;
    material_index      : int = -1;
    mode                : Gltf_Primitive_Mode = .TRIANGLES;
}

Gltf_Mesh :: struct {
    name       : string;
    primitives : [..] Gltf_Primitive;
}

// so our struct names mirror what's in the file but it might be better to not do that and be explict, but then you have to know the mapping 
// from the custom name to the thing in the file, but I don't think there's a problem with that, because the code becomes easier to understand.

Gltf_Texture_Info :: struct {
    texture_index : int = -1;
    texcoord      : int;        // which TEXCOORD_n channel to use
}

Gltf_Normal_Texture_Info :: struct {
    texture_index : int = -1;
    texcoord      : int;        // which TEXCOORD_n channel to use
    scale         : float = 1.0;
}

Gltf_Occlusion_Texture_Info :: struct {
    texture_index : int = -1;
    texcoord      : int;        // which TEXCOORD_n channel to use
    strength      : float = 1.0;
}

Gltf_Pbr_Metallic_Roughness :: struct {
    base_color_factor   : Vector4 = .{1, 1, 1, 1};
    base_color_texture  : Gltf_Texture_Info;
    metallic_factor     : float = 1.0;
    roughness_factor    : float = 1.0;
    metallic_roughness_texture : Gltf_Texture_Info;
}


/*
This information here is what gltf can express in terms of a material
by invoking the usage of some gltf extensions. Generally this is pretty much just pbr
but it also allows you do do glass and other things too.
*/ 
Gltf_Material :: struct {
    name : string;

    // classic pbr:
    pbr_metallic_roughness : Gltf_Pbr_Metallic_Roughness;
    normal_texture    : Gltf_Normal_Texture_Info;
    occlusion_texture : Gltf_Occlusion_Texture_Info;

    // objects that give off light
    emissive_texture  : Gltf_Texture_Info; // a texture telling how light should be emitted from a surface
    emissive_factor   : Vector3 = .{0, 0, 0}; // a multiplier on those light values

    // objects that have tranparency
    alpha_mode   : Gltf_Alpha_Mode = .OPAQUE;
    alpha_cutoff : float = 0.5; // todo rename to alpha_cutoff_for_mask
    double_sided : bool; // when both sides of a triangle should render or only one side should

    // seethrough objects such as glass and liquids
    transmission_factor : float = 0.0; // how much light passes through a material
    ior                 : float = 1.5; // index_of_refraction, how much light bends and how strong fresnel reflection is
    thickness_factor    : float = 0.0; // thickness of the volume behind the surface
    attenuation_distance: float = 1000000.0; // how far light travels through the material before being significantly absorbed.
    attenuation_color   : Vector3 = .{1, 1, 1}; // the color 
}

Gltf_Texture :: struct {
    sampler_index : int = -1;
    source_index  : int = -1;
    name          : string;
}

Gltf_Image :: struct {
    uri       : string;
    mime_type : string;
    name      : string;
}

Gltf_Sampler :: struct {
    mag_filter : Gltf_Texture_Filter = .LINEAR;
    min_filter : Gltf_Texture_Filter = .LINEAR_MIPMAP_LINEAR;
    wrap_s     : Gltf_Texture_Wrap   = .REPEAT;
    wrap_t     : Gltf_Texture_Wrap   = .REPEAT;
    name       : string;
}

Gltf_Node :: struct {
    name          : string;
    mesh_index    : int = -1;
    light_index   : int = -1;
    children      : [..] int;

    translation   : Vector3 = .{0, 0, 0};
    rotation      : Quaternion = .{0, 0, 0, 1};
    scale         : Vector3 = .{1, 1, 1};

    skin_index    : int = -1;

    has_matrix    : bool;
    matrix        : Matrix4;
}

Gltf_Light :: struct {
    name       : string;
    light_type : Gltf_Light_Type = .POINT;
    color      : Vector3 = .{1, 1, 1};
    intensity  : float = 1.0;
    range      : float = 0.0;
    inner_cone_angle : float = 0.0;
    outer_cone_angle : float = 0.78539819;
}

Gltf_Scene :: struct {
    name  : string;
    nodes : [..] int;
}

Gltf_Data :: struct {
    all_buffers       : [..] Gltf_Buffer;
    all_buffer_views  : [..] Gltf_Buffer_View;
    all_accessors     : [..] Gltf_Accessor;
    all_meshes        : [..] Gltf_Mesh;
    all_materials     : [..] Gltf_Material;
    all_lights        : [..] Gltf_Light;
    all_textures      : [..] Gltf_Texture;
    all_images        : [..] Gltf_Image;
    all_samplers      : [..] Gltf_Sampler;
    all_nodes         : [..] Gltf_Node;
    all_scenes        : [..] Gltf_Scene;
    all_skins         : [..] Gltf_Skin;
    all_animations    : [..] Gltf_Animation;

    default_scene     : int = -1;

    directory         : string;
}

deinit :: (gltf: *Gltf_Data) {
    for * gltf.all_buffers {
        if it.uri.count > 0 free(it.uri);
        if it.loaded_data.count > 0 free(it.loaded_data);
    }
    array_free(gltf.all_buffers);

    array_free(gltf.all_buffer_views);
    array_free(gltf.all_accessors);

    for * mesh: gltf.all_meshes {
        if mesh.name.count > 0 free(mesh.name);
        for * primitive: mesh.primitives {
            array_free(primitive.texcoord_accessors);
            array_free(primitive.joints_accessors);
            array_free(primitive.weights_accessors);
        }
        array_free(mesh.primitives);
    }
    array_free(gltf.all_meshes);

    for * material: gltf.all_materials {
        if material.name.count > 0 free(material.name);
    }
    array_free(gltf.all_materials);

    for * light: gltf.all_lights {
        if light.name.count > 0 free(light.name);
    }
    array_free(gltf.all_lights);

    for * texture: gltf.all_textures {
        if texture.name.count > 0 free(texture.name);
    }
    array_free(gltf.all_textures);

    for * image: gltf.all_images {
        if image.uri.count > 0 free(image.uri);
        if image.mime_type.count > 0 free(image.mime_type);
        if image.name.count > 0 free(image.name);
    }
    array_free(gltf.all_images);

    for * sampler: gltf.all_samplers {
        if sampler.name.count > 0 free(sampler.name);
    }
    array_free(gltf.all_samplers);

    for * node: gltf.all_nodes {
        if node.name.count > 0 free(node.name);
        array_free(node.children);
    }
    array_free(gltf.all_nodes);

    for * scene: gltf.all_scenes {
        if scene.name.count > 0 free(scene.name);
        array_free(scene.nodes);
    }
    array_free(gltf.all_scenes);

    for * skin: gltf.all_skins {
        if skin.name.count > 0 free(skin.name);
        array_free(skin.joints);
    }
    array_free(gltf.all_skins);

    for * animation: gltf.all_animations {
        if animation.name.count > 0 free(animation.name);
        array_free(animation.samplers);
        array_free(animation.channels);
    }
    array_free(gltf.all_animations);

    if gltf.directory.count > 0 free(gltf.directory);
    gltf.* = .{};
}

Gltf_Skin :: struct {
    name                     : string;
    joints                   : [..] int;    // node indices that act as bones
    inverse_bind_matrices    : int = -1;    // accessor index for the IBMs
    skeleton_root            : int = -1;    // node index of the skeleton root (optional)
}

Gltf_Animation_Sampler :: struct {
    input_accessor   : int = -1;   // accessor for keyframe timestamps
    output_accessor  : int = -1;   // accessor for keyframe values
    interpolation    : Gltf_Interpolation = .LINEAR;
}

Gltf_Animation_Channel :: struct {
    sampler_index : int = -1;
    target_node   : int = -1;
    target_path   : Gltf_Animation_Path = .TRANSLATION;
}

Gltf_Animation :: struct {
    name     : string;
    samplers : [..] Gltf_Animation_Sampler;
    channels : [..] Gltf_Animation_Channel;
}

// loading

load_gltf :: (path_to_gltf_file: string) -> Gltf_Data {
    success, file_contents := load_asset(path_to_gltf_file);
    assert(success, "couldn't open the gltf file");

    gltf_data: Gltf_Data;

    // extract directory
    last_slash := find_index_from_right(path_to_gltf_file, #char "/");
    if last_slash >= 0 {
        dir: string;
        dir.data = path_to_gltf_file.data;
        dir.count = last_slash + 1;
        gltf_data.directory = copy_string(dir);
    } else {
        gltf_data.directory = copy_string("");
    }

    // parse the JSON using the json library
    root := json_parse(file_contents);
    defer json_free(root);

    // parse each top-level section
    parse_buffers(*gltf_data, root);
    parse_buffer_views(*gltf_data, root);
    parse_accessors(*gltf_data, root);
    parse_images(*gltf_data, root);
    parse_samplers(*gltf_data, root);
    parse_textures(*gltf_data, root);
    parse_materials(*gltf_data, root);
    parse_lights(*gltf_data, root);
    parse_meshes(*gltf_data, root);
    parse_nodes(*gltf_data, root);
    parse_skins(*gltf_data, root);
    parse_animations(*gltf_data, root);
    parse_scenes(*gltf_data, root);

    // default scene
    scene_val := json_get(root, "scene");
    if scene_val && json_is_number(scene_val) {
        gltf_data.default_scene = json_get_int(root, "scene");
    }

    // load binary buffer data from external files
    load_buffer_data(*gltf_data);

    return gltf_data;
}

read_gltf_skin_weights :: (
    gltf: *Gltf_Data,
    prim: *Gltf_Primitive,
    out_bone_indices: *[..] [4] u32,
    out_bone_weights: *[..] [4] float32
) {
    if prim.joints_accessors.count == 0 || prim.weights_accessors.count == 0 return;

    // Read JOINTS_0 and WEIGHTS_0 (we support the first set for now)
    joints_accessor := prim.joints_accessors[0];
    weights_accessor := prim.weights_accessors[0];

    joints := read_accessor_as_u32x4_array(gltf, joints_accessor);
    weights := read_accessor_as_f32x4_array(gltf, weights_accessor);
    defer array_free(joints);
    defer array_free(weights);

    count := min(joints.count, weights.count);
    array_reserve(out_bone_indices, count);
    array_reserve(out_bone_weights, count);

    for i: 0..count - 1 {
        array_add(out_bone_indices, joints[i]);
        array_add(out_bone_weights, weights[i]);
    }
}

// gltf section parsers

#scope_file

// helper to read a number from a bare json_value (e.g. an array element).
// the library's typed getters like json_get_number() work on object+key pairs,
// so for raw values from json_array_get() we access .number directly.
json_value_as_float :: (val: *Json_Value) -> float {
    if val == null return 0;
    return cast(float) val.number;
}

json_value_as_int :: (val: *Json_Value) -> int {
    if val == null return 0;
    return cast(int) val.number;
}

hex_value :: (c: u8) -> int, bool {
    if c >= #char "0" && c <= #char "9" return cast(int)(c - #char "0"), true;
    if c >= #char "a" && c <= #char "f" return 10 + cast(int)(c - #char "a"), true;
    if c >= #char "A" && c <= #char "F" return 10 + cast(int)(c - #char "A"), true;
    return 0, false;
}

decode_uri_path :: (uri: string) -> string {
    decoded := alloc_string(uri.count);
    out_count := 0;

    i := 0;
    while i < uri.count {
        if uri[i] == #char "%" && i + 2 < uri.count {
            hi, hi_ok := hex_value(uri[i + 1]);
            lo, lo_ok := hex_value(uri[i + 2]);
            if hi_ok && lo_ok {
                decoded[out_count] = cast(u8)((hi << 4) | lo);
                out_count += 1;
                i += 3;
                continue;
            }
        }

        decoded[out_count] = uri[i];
        out_count += 1;
        i += 1;
    }

    decoded.count = out_count;
    normalize_slashes(decoded);
    return decoded;
}

parse_lights :: (gltf: *Gltf_Data, root: *Json_Value) {
    extensions := json_get_object(root, "extensions");
    if extensions == null return;

    punctual := json_get_object(extensions, "KHR_lights_punctual");
    if punctual == null return;

    lights_arr := json_get_array(punctual, "lights");
    if lights_arr == null return;

    for i: 0..json_array_count(lights_arr) - 1 {
        light_json := json_array_get(lights_arr, i);
        light: Gltf_Light;
        light.name = copy_string(json_get_string(light_json, "name"));

        type_str := json_get_string(light_json, "type", "point");
        if type_str == "directional" light.light_type = .DIRECTIONAL;
        else if type_str == "spot"  light.light_type = .SPOT;
        else                         light.light_type = .POINT;

        color_arr := json_get_array(light_json, "color");
        if color_arr && json_array_count(color_arr) >= 3 {
            light.color.x = json_value_as_float(json_array_get(color_arr, 0));
            light.color.y = json_value_as_float(json_array_get(color_arr, 1));
            light.color.z = json_value_as_float(json_array_get(color_arr, 2));
        }

        light.intensity = cast(float) json_get_number(light_json, "intensity", 1.0);
        light.range = cast(float) json_get_number(light_json, "range", 0.0);

        spot_json := json_get_object(light_json, "spot");
        if spot_json {
            light.inner_cone_angle = cast(float) json_get_number(spot_json, "innerConeAngle", 0.0);
            light.outer_cone_angle = cast(float) json_get_number(spot_json, "outerConeAngle", 0.78539816339);
        }

        array_add(*gltf.all_lights, light);
    }
}

parse_buffers :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "buffers");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        buf_json := json_array_get(arr, i);
        buf: Gltf_Buffer;
        buf.uri = copy_string(json_get_string(buf_json, "uri"));
        buf.byte_length = json_get_int(buf_json, "byteLength");
        array_add(*gltf.all_buffers, buf);
    }
}

parse_buffer_views :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "bufferViews");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        bv_json := json_array_get(arr, i);
        bv: Gltf_Buffer_View;
        bv.buffer_index = json_get_int(bv_json, "buffer");
        bv.byte_offset  = json_get_int(bv_json, "byteOffset");
        bv.byte_length  = json_get_int(bv_json, "byteLength");
        bv.byte_stride  = json_get_int(bv_json, "byteStride");
        array_add(*gltf.all_buffer_views, bv);
    }
}

parse_accessors :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "accessors");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        acc_json := json_array_get(arr, i);
        acc: Gltf_Accessor;

        bv_val := json_get(acc_json, "bufferView");
        if bv_val && json_is_number(bv_val) {
            acc.buffer_view_index = json_get_int(acc_json, "bufferView");
        }

        acc.byte_offset    = json_get_int(acc_json, "byteOffset");
        acc.count          = json_get_int(acc_json, "count");
        acc.component_type = cast(Gltf_Component_Type) json_get_int(acc_json, "componentType", 5126);
        acc.normalized     = json_get_bool(acc_json, "normalized");

        type_str := json_get_string(acc_json, "type", "SCALAR");
        acc.accessor_type = string_to_accessor_type(type_str);

        array_add(*gltf.all_accessors, acc);
    }
}

string_to_accessor_type :: (s: string) -> Gltf_Accessor_Type {
    if s == "SCALAR" return .SCALAR;
    if s == "VEC2"   return .VEC2;
    if s == "VEC3"   return .VEC3;
    if s == "VEC4"   return .VEC4;
    if s == "MAT2"   return .MAT2;
    if s == "MAT3"   return .MAT3;
    if s == "MAT4"   return .MAT4;
    return .SCALAR;
}

parse_meshes :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "meshes");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        mesh_json := json_array_get(arr, i);
        mesh: Gltf_Mesh;
        mesh.name = copy_string(json_get_string(mesh_json, "name"));

        prims_arr := json_get_array(mesh_json, "primitives");
        if prims_arr {
            for pi: 0..json_array_count(prims_arr) - 1 {
                prim_json := json_array_get(prims_arr, pi);
                prim: Gltf_Primitive;

                // attributes
                attrs := json_get_object(prim_json, "attributes");
                if attrs {
                    pos_val := json_get(attrs, "POSITION");
                    if pos_val && json_is_number(pos_val)  then prim.position_accessor = json_get_int(attrs, "POSITION");

                    norm_val := json_get(attrs, "NORMAL");
                    if norm_val && json_is_number(norm_val) then prim.normal_accessor = json_get_int(attrs, "NORMAL");

                    tan_val := json_get(attrs, "TANGENT");
                    if tan_val && json_is_number(tan_val)  then prim.tangent_accessor = json_get_int(attrs, "TANGENT");

                    // multi-channel UV support: scan TEXCOORD_0 through TEXCOORD_(MAX_TEXCOORD_CHANNELS-1)
                    for tc_index: 0..MAX_TEXCOORD_CHANNELS - 1 {
                        tc_name := tprint("TEXCOORD_%", tc_index);
                        tc_val := json_get(attrs, tc_name);
                        if tc_val && json_is_number(tc_val) {
                            // Ensure the array is large enough — fill gaps with -1
                            while prim.texcoord_accessors.count <= tc_index {
                                array_add(*prim.texcoord_accessors, -1);
                            }
                            prim.texcoord_accessors[tc_index] = json_get_int(attrs, tc_name);
                        } else {
                            // Stop scanning if there's a gap (conservative) — or continue to allow sparse.
                            // glTF spec says TEXCOORD sets should be contiguous starting from 0,
                            // but we'll be lenient and keep scanning.
                        }
                    }

                    // skinning attributes: joints_0..n and weights_0..n
                    for jw_index: 0..3 {  // up to 4 sets
                        joints_name := tprint("JOINTS_%", jw_index);
                        j_val := json_get(attrs, joints_name);
                        if j_val && json_is_number(j_val) {
                            while prim.joints_accessors.count <= jw_index {
                                array_add(*prim.joints_accessors, -1);
                            }
                            prim.joints_accessors[jw_index] = json_get_int(attrs, joints_name);
                        }

                        weights_name := tprint("WEIGHTS_%", jw_index);
                        w_val := json_get(attrs, weights_name);
                        if w_val && json_is_number(w_val) {
                            while prim.weights_accessors.count <= jw_index {
                                array_add(*prim.weights_accessors, -1);
                            }
                            prim.weights_accessors[jw_index] = json_get_int(attrs, weights_name);
                        }
                    }


                }

                idx_val := json_get(prim_json, "indices");
                if idx_val && json_is_number(idx_val) then prim.indices_accessor = json_get_int(prim_json, "indices");

                mat_val := json_get(prim_json, "material");
                if mat_val && json_is_number(mat_val) then prim.material_index = json_get_int(prim_json, "material");

                mode_val := json_get(prim_json, "mode");
                if mode_val && json_is_number(mode_val) {
                    prim.mode = cast(Gltf_Primitive_Mode) cast(u32) json_get_int(prim_json, "mode");
                }

                array_add(*mesh.primitives, prim);
            }
        }

        array_add(*gltf.all_meshes, mesh);
    }
}

parse_materials :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "materials");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        mat_json := json_array_get(arr, i);
        mat: Gltf_Material;
        mat.name = copy_string(json_get_string(mat_json, "name"));

        // PBR metallic roughness
        pbr := json_get_object(mat_json, "pbrMetallicRoughness");
        if pbr {
            bcf := json_get_array(pbr, "baseColorFactor");
            if bcf && json_array_count(bcf) >= 4 {
                mat.pbr_metallic_roughness.base_color_factor.x = json_value_as_float(json_array_get(bcf, 0));
                mat.pbr_metallic_roughness.base_color_factor.y = json_value_as_float(json_array_get(bcf, 1));
                mat.pbr_metallic_roughness.base_color_factor.z = json_value_as_float(json_array_get(bcf, 2));
                mat.pbr_metallic_roughness.base_color_factor.w = json_value_as_float(json_array_get(bcf, 3));
            }

            mat.pbr_metallic_roughness.metallic_factor  = cast(float) json_get_number(pbr, "metallicFactor", 1.0);
            mat.pbr_metallic_roughness.roughness_factor = cast(float) json_get_number(pbr, "roughnessFactor", 1.0);

            bct := json_get_object(pbr, "baseColorTexture");
            if bct then mat.pbr_metallic_roughness.base_color_texture = parse_texture_info(bct);

            mrt := json_get_object(pbr, "metallicRoughnessTexture");
            if mrt then mat.pbr_metallic_roughness.metallic_roughness_texture = parse_texture_info(mrt);
        }

        // normal texture
        nt := json_get_object(mat_json, "normalTexture");
        if nt {
            mat.normal_texture.texture_index = json_get_int(nt, "index", -1);
            mat.normal_texture.texcoord      = json_get_int(nt, "texCoord");
            mat.normal_texture.scale         = cast(float) json_get_number(nt, "scale", 1.0);
        }

        // occlusion texture
        ot := json_get_object(mat_json, "occlusionTexture");
        if ot {
            mat.occlusion_texture.texture_index = json_get_int(ot, "index", -1);
            mat.occlusion_texture.texcoord      = json_get_int(ot, "texCoord");
            mat.occlusion_texture.strength      = cast(float) json_get_number(ot, "strength", 1.0);
        }

        // emissive texture
        et := json_get_object(mat_json, "emissiveTexture");
        if et then mat.emissive_texture = parse_texture_info(et);

        // emissive factor
        ef := json_get_array(mat_json, "emissiveFactor");
        if ef && json_array_count(ef) >= 3 {
            mat.emissive_factor.x = json_value_as_float(json_array_get(ef, 0));
            mat.emissive_factor.y = json_value_as_float(json_array_get(ef, 1));
            mat.emissive_factor.z = json_value_as_float(json_array_get(ef, 2));
        }

        // alpha
        alpha_str := json_get_string(mat_json, "alphaMode", "OPAQUE");
        if alpha_str == "MASK"   then mat.alpha_mode = .MASK;
        if alpha_str == "BLEND"  then mat.alpha_mode = .BLEND;
        mat.alpha_cutoff = cast(float) json_get_number(mat_json, "alphaCutoff", 0.5);
        mat.double_sided = json_get_bool(mat_json, "doubleSided");

        extensions := json_get_object(mat_json, "extensions");
        if extensions {
            transmission := json_get_object(extensions, "KHR_materials_transmission");
            if transmission {
                mat.transmission_factor = cast(float) json_get_number(transmission, "transmissionFactor", 0.0);
            }

            ior := json_get_object(extensions, "KHR_materials_ior");
            if ior {
                mat.ior = cast(float) json_get_number(ior, "ior", 1.5);
            }

            volume := json_get_object(extensions, "KHR_materials_volume");
            if volume {
                mat.thickness_factor = cast(float) json_get_number(volume, "thicknessFactor", 0.0);
                mat.attenuation_distance = cast(float) json_get_number(volume, "attenuationDistance", 1000000.0);

                attenuation_color := json_get_array(volume, "attenuationColor");
                if attenuation_color && json_array_count(attenuation_color) >= 3 {
                    mat.attenuation_color.x = json_value_as_float(json_array_get(attenuation_color, 0));
                    mat.attenuation_color.y = json_value_as_float(json_array_get(attenuation_color, 1));
                    mat.attenuation_color.z = json_value_as_float(json_array_get(attenuation_color, 2));
                }
            }
        }

        array_add(*gltf.all_materials, mat);
    }
}

parse_texture_info :: (json: *Json_Value) -> Gltf_Texture_Info {
    info: Gltf_Texture_Info;
    if json == null || !json_is_object(json) return info;
    info.texture_index = json_get_int(json, "index", -1);
    info.texcoord      = json_get_int(json, "texCoord");
    return info;
}

parse_textures :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "textures");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        tex_json := json_array_get(arr, i);
        tex: Gltf_Texture;
        tex.name = copy_string(json_get_string(tex_json, "name"));

        sampler_val := json_get(tex_json, "sampler");
        if sampler_val && json_is_number(sampler_val) then tex.sampler_index = json_get_int(tex_json, "sampler");

        source_val := json_get(tex_json, "source");
        if source_val && json_is_number(source_val) then tex.source_index = json_get_int(tex_json, "source");

        array_add(*gltf.all_textures, tex);
    }
}

parse_images :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "images");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        img_json := json_array_get(arr, i);
        img: Gltf_Image;
        img.uri       = copy_string(json_get_string(img_json, "uri"));
        img.mime_type = copy_string(json_get_string(img_json, "mimeType"));
        img.name      = copy_string(json_get_string(img_json, "name"));
        array_add(*gltf.all_images, img);
    }
}

parse_samplers :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "samplers");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        samp_json := json_array_get(arr, i);
        samp: Gltf_Sampler;
        samp.name = copy_string(json_get_string(samp_json, "name"));

        mag_val := json_get(samp_json, "magFilter");
        if mag_val && json_is_number(mag_val) then samp.mag_filter = cast(Gltf_Texture_Filter) cast(u32) json_get_int(samp_json, "magFilter");

        min_val := json_get(samp_json, "minFilter");
        if min_val && json_is_number(min_val) then samp.min_filter = cast(Gltf_Texture_Filter) cast(u32) json_get_int(samp_json, "minFilter");

        wrap_s_val := json_get(samp_json, "wrapS");
        if wrap_s_val && json_is_number(wrap_s_val) then samp.wrap_s = cast(Gltf_Texture_Wrap) cast(u32) json_get_int(samp_json, "wrapS");

        wrap_t_val := json_get(samp_json, "wrapT");
        if wrap_t_val && json_is_number(wrap_t_val) then samp.wrap_t = cast(Gltf_Texture_Wrap) cast(u32) json_get_int(samp_json, "wrapT");

        array_add(*gltf.all_samplers, samp);
    }
}

parse_nodes :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "nodes");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        node_json := json_array_get(arr, i);
        node: Gltf_Node;
        node.name = copy_string(json_get_string(node_json, "name"));

        mesh_val := json_get(node_json, "mesh");
        if mesh_val && json_is_number(mesh_val) then node.mesh_index = json_get_int(node_json, "mesh");

        extensions := json_get_object(node_json, "extensions");
        if extensions {
            punctual := json_get_object(extensions, "KHR_lights_punctual");
            if punctual {
                light_val := json_get(punctual, "light");
                if light_val && json_is_number(light_val) then node.light_index = json_get_int(punctual, "light");
            }
        }

        skin_val := json_get(node_json, "skin");
        if skin_val && json_is_number(skin_val) then node.skin_index = json_get_int(node_json, "skin");

        // children
        children_arr := json_get_array(node_json, "children");
        if children_arr {
            for ci: 0..json_array_count(children_arr) - 1 {
                child := json_array_get(children_arr, ci);
                if child && json_is_number(child) {
                    array_add(*node.children, json_value_as_int(child));
                }
            }
        }

        // matrix
        matrix_arr := json_get_array(node_json, "matrix");
        if matrix_arr && json_array_count(matrix_arr) == 16 {
            node.has_matrix = true;
            for mi: 0..15 {
                val := json_array_get(matrix_arr, mi);
                // glTF stores column-major, which matches how we'll store it
                col := mi / 4;
                row := mi % 4;
                node.matrix.coef[row][col] = json_value_as_float(val);
            }
        } else {
            node.has_matrix = false;

            // translation
            t_arr := json_get_array(node_json, "translation");
            if t_arr && json_array_count(t_arr) >= 3 {
                node.translation.x = json_value_as_float(json_array_get(t_arr, 0));
                node.translation.y = json_value_as_float(json_array_get(t_arr, 1));
                node.translation.z = json_value_as_float(json_array_get(t_arr, 2));
            }

            // rotation (quaternion xyzw)
            r_arr := json_get_array(node_json, "rotation");
            if r_arr && json_array_count(r_arr) >= 4 {
                node.rotation.x = json_value_as_float(json_array_get(r_arr, 0));
                node.rotation.y = json_value_as_float(json_array_get(r_arr, 1));
                node.rotation.z = json_value_as_float(json_array_get(r_arr, 2));
                node.rotation.w = json_value_as_float(json_array_get(r_arr, 3));
            }

            // scale
            s_arr := json_get_array(node_json, "scale");
            if s_arr && json_array_count(s_arr) >= 3 {
                node.scale.x = json_value_as_float(json_array_get(s_arr, 0));
                node.scale.y = json_value_as_float(json_array_get(s_arr, 1));
                node.scale.z = json_value_as_float(json_array_get(s_arr, 2));
            }
        }

        array_add(*gltf.all_nodes, node);
    }
}

parse_scenes :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "scenes");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        scene_json := json_array_get(arr, i);
        scene: Gltf_Scene;
        scene.name = copy_string(json_get_string(scene_json, "name"));

        nodes_arr := json_get_array(scene_json, "nodes");
        if nodes_arr {
            for ni: 0..json_array_count(nodes_arr) - 1 {
                node_val := json_array_get(nodes_arr, ni);
                if node_val && json_is_number(node_val) {
                    array_add(*scene.nodes, json_value_as_int(node_val));
                }
            }
        }

        array_add(*gltf.all_scenes, scene);
    }
}

parse_skins :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "skins");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        skin_json := json_array_get(arr, i);
        skin: Gltf_Skin;
        skin.name = copy_string(json_get_string(skin_json, "name"));

        ibm_val := json_get(skin_json, "inverseBindMatrices");
        if ibm_val && json_is_number(ibm_val) {
            skin.inverse_bind_matrices = json_get_int(skin_json, "inverseBindMatrices");
        }

        skel_val := json_get(skin_json, "skeleton");
        if skel_val && json_is_number(skel_val) {
            skin.skeleton_root = json_get_int(skin_json, "skeleton");
        }

        joints_arr := json_get_array(skin_json, "joints");
        if joints_arr {
            for ji: 0..json_array_count(joints_arr) - 1 {
                joint_val := json_array_get(joints_arr, ji);
                if joint_val && json_is_number(joint_val) {
                    array_add(*skin.joints, json_value_as_int(joint_val));
                }
            }
        }

        array_add(*gltf.all_skins, skin);
    }
}

parse_animations :: (gltf: *Gltf_Data, root: *Json_Value) {
    arr := json_get_array(root, "animations");
    if arr == null return;

    for i: 0..json_array_count(arr) - 1 {
        anim_json := json_array_get(arr, i);
        anim: Gltf_Animation;
        anim.name = copy_string(json_get_string(anim_json, "name"));

        // parse samplers
        samplers_arr := json_get_array(anim_json, "samplers");
        if samplers_arr {
            for si: 0..json_array_count(samplers_arr) - 1 {
                samp_json := json_array_get(samplers_arr, si);
                samp: Gltf_Animation_Sampler;

                input_val := json_get(samp_json, "input");
                if input_val && json_is_number(input_val) {
                    samp.input_accessor = json_get_int(samp_json, "input");
                }

                output_val := json_get(samp_json, "output");
                if output_val && json_is_number(output_val) {
                    samp.output_accessor = json_get_int(samp_json, "output");
                }

                interp_str := json_get_string(samp_json, "interpolation", "LINEAR");
                if interp_str == "STEP"        then samp.interpolation = .STEP;
                else if interp_str == "CUBICSPLINE" then samp.interpolation = .CUBICSPLINE;
                else samp.interpolation = .LINEAR;

                array_add(*anim.samplers, samp);
            }
        }

        // parse channels
        channels_arr := json_get_array(anim_json, "channels");
        if channels_arr {
            for ci: 0..json_array_count(channels_arr) - 1 {
                chan_json := json_array_get(channels_arr, ci);
                chan: Gltf_Animation_Channel;

                sampler_val := json_get(chan_json, "sampler");
                if sampler_val && json_is_number(sampler_val) {
                    chan.sampler_index = json_get_int(chan_json, "sampler");
                }

                target_json := json_get_object(chan_json, "target");
                if target_json {
                    node_val := json_get(target_json, "node");
                    if node_val && json_is_number(node_val) {
                        chan.target_node = json_get_int(target_json, "node");
                    }

                    path_str := json_get_string(target_json, "path", "");
                    if path_str == "translation"      then chan.target_path = .TRANSLATION;
                    else if path_str == "rotation"    then chan.target_path = .ROTATION;
                    else if path_str == "scale"       then chan.target_path = .SCALE;
                    else if path_str == "weights"     then chan.target_path = .WEIGHTS;
                }

                array_add(*anim.channels, chan);
            }
        }

        array_add(*gltf.all_animations, anim);
    }
}


// binary buffer loading

load_buffer_data :: (gltf: *Gltf_Data) {
    for * buf : gltf.all_buffers {
        if buf.uri.count == 0 continue;

        // we don't support data URIs
        if begins_with(buf.uri, "data:") {
            assert(false, "data URIs not supported in glTF loader");
            continue;
        }

            uri_path := decode_uri_path(buf.uri);
            defer free(uri_path);
            full_path := tprint("%1%2", gltf.directory, uri_path);
            success, data := load_asset_copy(full_path);
            assert(success, "couldn't load glTF buffer file");
            buf.loaded_data = data;
    }
}

#scope_export

// data access helpers

// these let you pull actual vertex data out of the binary buffers
// using the accessor/bufferview indirection that gltf uses.

get_accessor_data_pointer :: (gltf: *Gltf_Data, accessor_index: int) -> *u8, int {
    if accessor_index < 0 || accessor_index >= gltf.all_accessors.count return null, 0;

    acc := *gltf.all_accessors[accessor_index];
    if acc.buffer_view_index < 0 return null, 0;

    bv := *gltf.all_buffer_views[acc.buffer_view_index];
    buf := *gltf.all_buffers[bv.buffer_index];

    offset := bv.byte_offset + acc.byte_offset;
    ptr := buf.loaded_data.data + offset;

    stride := bv.byte_stride;
    if stride == 0 {
        stride = get_accessor_element_size(acc);
    }

    return ptr, stride;
}

get_component_size :: (component_type: Gltf_Component_Type) -> int {
    if component_type == {
        case .BYTE;           return 1;
        case .UNSIGNED_BYTE;  return 1;
        case .SHORT;          return 2;
        case .UNSIGNED_SHORT; return 2;
        case .UNSIGNED_INT;   return 4;
        case .FLOAT;          return 4;
    }
    return 0;
}

get_component_count :: (accessor_type: Gltf_Accessor_Type) -> int {
    if accessor_type == {
        case .SCALAR; return 1;
        case .VEC2;   return 2;
        case .VEC3;   return 3;
        case .VEC4;   return 4;
        case .MAT2;   return 4;
        case .MAT3;   return 9;
        case .MAT4;   return 16;
    }
    return 0;
}

get_accessor_element_size :: (acc: *Gltf_Accessor) -> int {
    return get_component_size(acc.component_type) * get_component_count(acc.accessor_type);
}

read_accessor_as_vector3_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] Vector3 {
    result: [..] Vector3;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        v: Vector3;
        if acc.component_type == .FLOAT {
            float_ptr := cast(*float) element_ptr;
            v.x = float_ptr[0];
            v.y = float_ptr[1];
            if acc.accessor_type == .VEC3 || acc.accessor_type == .VEC4 {
                v.z = float_ptr[2];
            }
        }
        array_add(*result, v);
    }
    return result;
}

read_accessor_as_vector2_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] Vector2 {
    result: [..] Vector2;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        v: Vector2;
        if acc.component_type == .FLOAT {
            float_ptr := cast(*float) element_ptr;
            v.x = float_ptr[0];
            v.y = float_ptr[1];
        }
        array_add(*result, v);
    }
    return result;
}

read_accessor_as_vector4_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] Vector4 {
    result: [..] Vector4;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        v: Vector4;
        if acc.component_type == .FLOAT {
            float_ptr := cast(*float) element_ptr;
            v.x = float_ptr[0];
            v.y = float_ptr[1];
            v.z = float_ptr[2];
            v.w = float_ptr[3];
        }
        array_add(*result, v);
    }
    return result;
}

read_accessor_as_u32x4_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] [4] u32 {
    result: [..] [4] u32;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        v: [4] u32;

        if acc.component_type == {
            case .UNSIGNED_BYTE;
                for k: 0..3 v[k] = cast(u32) element_ptr[k];
            case .UNSIGNED_SHORT;
                short_ptr := cast(*u16) element_ptr;
                for k: 0..3 v[k] = cast(u32) short_ptr[k];
            case .UNSIGNED_INT;
                uint_ptr := cast(*u32) element_ptr;
                for k: 0..3 v[k] = uint_ptr[k];
            case .FLOAT;
                float_ptr := cast(*float) element_ptr;
                for k: 0..3 v[k] = cast(u32) float_ptr[k];
        }

        array_add(*result, v);
    }
    return result;
}

read_accessor_as_f32x4_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] [4] float32 {
    result: [..] [4] float32;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        v: [4] float32;

        if acc.component_type == {
            case .FLOAT;
                float_ptr := cast(*float) element_ptr;
                for k: 0..3 v[k] = float_ptr[k];
            case .UNSIGNED_BYTE;
                // normalized: 0..255 -> 0..1
                for k: 0..3 v[k] = cast(float32) element_ptr[k] / 255.0;
            case .UNSIGNED_SHORT;
                short_ptr := cast(*u16) element_ptr;
                for k: 0..3 v[k] = cast(float32) short_ptr[k] / 65535.0;
        }

        array_add(*result, v);
    }
    return result;
}

read_accessor_as_matrix4_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] Matrix4 {
    result: [..] Matrix4;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        mat: Matrix4;
        if acc.component_type == .FLOAT {
            float_ptr := cast(*float) element_ptr;
            // glTF stores matrices in column-major order
            for col: 0..3 {
                for row: 0..3 {
                    mat.coef[row][col] = float_ptr[col * 4 + row];
                }
            }
        }
        array_add(*result, mat);
    }
    return result;
}

read_accessor_as_quaternion_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] Quaternion {
    result: [..] Quaternion;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        q: Quaternion;
        if acc.component_type == .FLOAT {
            float_ptr := cast(*float) element_ptr;
            q.x = float_ptr[0];
            q.y = float_ptr[1];
            q.z = float_ptr[2];
            q.w = float_ptr[3];
        }
        array_add(*result, q);
    }
    return result;
}

read_accessor_as_index_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] u32 {
    result: [..] u32;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        index: u32;

        if acc.component_type == {
            case .UNSIGNED_BYTE;
                index = cast(u32) element_ptr[0];
            case .UNSIGNED_SHORT;
                index = cast(u32) (cast(*u16) element_ptr).*;
            case .UNSIGNED_INT;
                index = (cast(*u32) element_ptr).*;
        }

        array_add(*result, index);
    }
    return result;
}

read_accessor_as_float_array :: (gltf: *Gltf_Data, accessor_index: int) -> [..] float {
    result: [..] float;
    if accessor_index < 0 return result;

    acc := *gltf.all_accessors[accessor_index];
    ptr, stride := get_accessor_data_pointer(gltf, accessor_index);
    if ptr == null return result;

    array_reserve(*result, acc.count);
    for i: 0..acc.count - 1 {
        element_ptr := ptr + i * stride;
        val: float;
        if acc.component_type == .FLOAT {
            val = (cast(*float) element_ptr).*;
        }
        array_add(*result, val);
    }
    return result;
}

// convenience helpers

resolve_gltf_image_path :: (gltf: *Gltf_Data, texture_index: int) -> string {
    if texture_index < 0 || texture_index >= gltf.all_textures.count return "";
    tex := *gltf.all_textures[texture_index];
    if tex.source_index < 0 || tex.source_index >= gltf.all_images.count return "";
    img := *gltf.all_images[tex.source_index];
    if img.uri.count == 0 return "";
    uri_path := decode_uri_path(img.uri);
    defer free(uri_path);
    return tprint("%1%2", gltf.directory, uri_path);
}

get_gltf_material :: (gltf: *Gltf_Data, material_index: int) -> *Gltf_Material {
    if material_index < 0 || material_index >= gltf.all_materials.count return null;
    return *gltf.all_materials[material_index];
}

get_default_scene :: (gltf: *Gltf_Data) -> *Gltf_Scene {
    if gltf.default_scene >= 0 && gltf.default_scene < gltf.all_scenes.count {
        return *gltf.all_scenes[gltf.default_scene];
    }
    if gltf.all_scenes.count > 0 return *gltf.all_scenes[0];
    return null;
}

// multi-channel uv helpers

// returns the number of uv channels available on this primitive
get_texcoord_channel_count :: (prim: *Gltf_Primitive) -> int {
    return prim.texcoord_accessors.count;
}

// returns the accessor index for a given uv channel, or -1 if not present.
get_texcoord_accessor :: (prim: *Gltf_Primitive, channel: int) -> int {
    if channel < 0 || channel >= prim.texcoord_accessors.count return -1;
    return prim.texcoord_accessors[channel];
}

// reads uv data for a specific channel from a primitive.
// this is the primary way to get texture coordinates when you have multi-channel uvs.
read_primitive_texcoords :: (gltf: *Gltf_Data, prim: *Gltf_Primitive, channel: int = 0) -> [..] Vector2 {
    accessor_index := get_texcoord_accessor(prim, channel);
    return read_accessor_as_vector2_array(gltf, accessor_index);
}

// given a texture info (which contains a texcoord channel index), reads the
// appropriate uv channel from the primitive. this is useful when rendering:
// each texture reference in a material specifies which uv channel it wants.
read_texcoords_for_texture_info :: (gltf: *Gltf_Data, prim: *Gltf_Primitive, tex_info: Gltf_Texture_Info) -> [..] Vector2 {
    return read_primitive_texcoords(gltf, prim, tex_info.texcoord);
}

read_texcoords_for_normal_texture :: (gltf: *Gltf_Data, prim: *Gltf_Primitive, tex_info: Gltf_Normal_Texture_Info) -> [..] Vector2 {
    return read_primitive_texcoords(gltf, prim, tex_info.texcoord);
}

read_texcoords_for_occlusion_texture :: (gltf: *Gltf_Data, prim: *Gltf_Primitive, tex_info: Gltf_Occlusion_Texture_Info) -> [..] Vector2 {
    return read_primitive_texcoords(gltf, prim, tex_info.texcoord);
}
