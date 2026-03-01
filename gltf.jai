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
    OPAQUE;
    MASK;
    BLEND;
}

// data structures

Gltf_Buffer :: struct {
    uri         : string;
    byte_length : int;
    loaded_data : string;  // raw bytes loaded from the .bin file
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

Gltf_Material :: struct {
    name : string;

    pbr_metallic_roughness : Gltf_Pbr_Metallic_Roughness;

    normal_texture    : Gltf_Normal_Texture_Info;
    occlusion_texture : Gltf_Occlusion_Texture_Info;
    emissive_texture  : Gltf_Texture_Info;
    emissive_factor   : Vector3 = .{0, 0, 0};

    alpha_mode   : Gltf_Alpha_Mode = .OPAQUE;
    alpha_cutoff : float = 0.5;
    double_sided : bool;
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
    children      : [..] int;

    translation   : Vector3 = .{0, 0, 0};
    rotation      : Quaternion = .{0, 0, 0, 1};
    scale         : Vector3 = .{1, 1, 1};

    has_matrix    : bool;
    matrix        : Matrix4;
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
    all_textures      : [..] Gltf_Texture;
    all_images        : [..] Gltf_Image;
    all_samplers      : [..] Gltf_Sampler;
    all_nodes         : [..] Gltf_Node;
    all_scenes        : [..] Gltf_Scene;

    default_scene     : int = -1;

    directory         : string;
}

// loading

load_gltf :: (path_to_gltf_file: string) -> Gltf_Data {
    file_contents, success := read_entire_file(path_to_gltf_file);
    assert(success, "couldn't open the gltf file");
    defer free(file_contents);

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
    parse_meshes(*gltf_data, root);
    parse_nodes(*gltf_data, root);
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

// binary buffer loading

load_buffer_data :: (gltf: *Gltf_Data) {
    for * buf : gltf.all_buffers {
        if buf.uri.count == 0 continue;

        // we don't support data URIs
        if begins_with(buf.uri, "data:") {
            assert(false, "data URIs not supported in glTF loader");
            continue;
        }

        full_path := tprint("%1%2", gltf.directory, buf.uri);
        data, success := read_entire_file(full_path);
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
    return tprint("%1%2", gltf.directory, img.uri);
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
