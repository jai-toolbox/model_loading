/*

MTL File Parser (Material Template Library)

This parses .mtl files that accompany .obj 3D model files.
These define surface material properties referenced by "usemtl" lines in .obj files.

Supported Properties (standard Wavefront MTL, non-PBR):

Declaration:
    newmtl <name>          -- Declares a new named material

Color & Illumination:
    Ka  r g b              -- Ambient color              (0.0–1.0 per channel)
    Kd  r g b              -- Diffuse color              (0.0–1.0 per channel)
    Ks  r g b              -- Specular color             (0.0–1.0 per channel)
    Ke  r g b              -- Emissive color             (0.0–1.0 per channel)
    Tf  r g b              -- Transmission filter color  (0.0–1.0 per channel)
    Ns  float              -- Specular exponent          (0–1000, higher = sharper highlight)
    Ni  float              -- Index of refraction        (0.001–10, 1.0 = no refraction)
    d   float              -- Dissolve / Opacity         (0.0 = transparent, 1.0 = opaque)
    Tr  float              -- Transparency (inverse of d)(0.0 = opaque, 1.0 = transparent)
    illum int              -- Illumination model         (0–10, see below)


    Why the hell does it use Ka Kd Ks Ke like what is the K for... Well one reason might be that
    K = Koeffizient, and the old lighting equations from physics used those because they were created 
    in Germany and then it was inherited all the way till now?

    Honestly not fully sure, but if we were to remake the .mtl format we wouldn't do this.

    The N seems to stand for Numerical, which is dumb, because everything is numerical, again we wouldn't do this given a second chance.


Illumination Models (illum):
    0  -- Color on, ambient off
    1  -- Color on, ambient on (diffuse only)
    2  -- Diffuse + specular (Phong) — most common
    3  -- Reflection on, ray trace on
    4  -- Transparency + glass, reflection + ray trace on
    5  -- Reflection + Fresnel, ray trace on
    6  -- Transparency + refraction, reflection + Fresnel off, ray trace on
    7  -- Transparency + refraction, reflection + Fresnel on, ray trace on
    8  -- Reflection on, ray trace off
    9  -- Transparency + glass, reflection + ray trace off
    10 -- Casts shadows onto invisible surfaces

Texture Maps:
    map_Ka   <file>        -- Ambient texture map
    map_Kd   <file>        -- Diffuse texture map (base color)
    map_Ks   <file>        -- Specular color texture map
    map_Ke   <file>        -- Emissive texture map
    map_Ns   <file>        -- Specular exponent texture map
    map_d    <file>        -- Alpha / Opacity texture map
    map_bump <file>        -- Bump map (grayscale height)
    bump     <file>        -- Bump map (alias for map_bump)
    disp     <file>        -- Displacement map
    decal    <file>        -- Stencil decal texture
    refl     <file>        -- Reflection / Environment map

Reference: https://paulbourke.net/dataformats/mtl/

*/

Mtl_Line_Type :: enum {
    UNKNOWN;
    COMMENT;
    NEW_MATERIAL;
    AMBIENT_COLOR;
    DIFFUSE_COLOR;
    SPECULAR_COLOR;
    EMISSIVE_COLOR;
    TRANSMISSION_FILTER;
    SPECULAR_EXPONENT;
    INDEX_OF_REFRACTION;
    DISSOLVE;
    TRANSPARENCY;
    ILLUMINATION_MODEL;
    MAP_AMBIENT;
    MAP_DIFFUSE;
    MAP_SPECULAR;
    MAP_EMISSIVE;
    MAP_SPECULAR_EXPONENT;
    MAP_DISSOLVE;
    MAP_BUMP;
    BUMP;
    DISPLACEMENT;
    DECAL;
    REFLECTION;
}

get_mtl_line_type :: (line: string) -> Mtl_Line_Type {
    if line.count == 0 return .UNKNOWN;

    if line[0] == #char "#" return .COMMENT;

    // texture maps first (longer prefixes before shorter to avoid false matches)
    if begins_with(line, "map_bump ") return .MAP_BUMP;
    if begins_with(line, "map_Kd ")   return .MAP_DIFFUSE;
    if begins_with(line, "map_Ka ")   return .MAP_AMBIENT;
    if begins_with(line, "map_Ks ")   return .MAP_SPECULAR;
    if begins_with(line, "map_Ke ")   return .MAP_EMISSIVE;
    if begins_with(line, "map_Ns ")   return .MAP_SPECULAR_EXPONENT;
    if begins_with(line, "map_d ")    return .MAP_DISSOLVE;

    // keywords with longer names first
    if begins_with(line, "newmtl ")   return .NEW_MATERIAL;
    if begins_with(line, "illum ")    return .ILLUMINATION_MODEL;
    if begins_with(line, "bump ")     return .BUMP;
    if begins_with(line, "disp ")     return .DISPLACEMENT;
    if begins_with(line, "decal ")    return .DECAL;
    if begins_with(line, "refl ")     return .REFLECTION;

    // color and scalar properties
    if begins_with(line, "Ka ")       return .AMBIENT_COLOR;
    if begins_with(line, "Kd ")       return .DIFFUSE_COLOR;
    if begins_with(line, "Ks ")       return .SPECULAR_COLOR;
    if begins_with(line, "Ke ")       return .EMISSIVE_COLOR;
    if begins_with(line, "Tf ")       return .TRANSMISSION_FILTER;
    if begins_with(line, "Ns ")       return .SPECULAR_EXPONENT;
    if begins_with(line, "Ni ")       return .INDEX_OF_REFRACTION;
    if begins_with(line, "d ")        return .DISSOLVE;
    if begins_with(line, "Tr ")       return .TRANSPARENCY;

    return .UNKNOWN;
}

Mtl_Material :: struct {
    name : string;

    // colors (RGB)
    ambient_color           : Vector3 = .{1.0, 1.0, 1.0};
    diffuse_color           : Vector3 = .{0.8, 0.8, 0.8};
    specular_color          : Vector3 = .{1.0, 1.0, 1.0};
    emissive_color          : Vector3 = .{0.0, 0.0, 0.0};
    transmission_filter     : Vector3 = .{1.0, 1.0, 1.0};

    // scalar properties
    specular_exponent       : float = 225.0;   // Ns, 0–1000
    index_of_refraction     : float = 1.0;     // Ni, 0.001–10
    dissolve                : float = 1.0;     // d,  0–1 (1 = opaque)
    illumination_model      : int   = 2;       // illum, 0–10

    // texture map file paths
    map_ambient             : string;
    map_diffuse             : string;
    map_specular            : string;
    map_emissive            : string;
    map_specular_exponent   : string;
    map_dissolve            : string;
    map_bump                : string;
    map_displacement        : string;
    map_decal               : string;
    map_reflection          : string;

    // flags indicating which properties were explicitly set in the file
    has_ambient_color           : bool;
    has_diffuse_color           : bool;
    has_specular_color          : bool;
    has_emissive_color          : bool;
    has_transmission_filter     : bool;
    has_specular_exponent       : bool;
    has_index_of_refraction     : bool;
    has_dissolve                : bool;
    has_illumination_model      : bool;
}

Mtl_Data :: struct {
    all_materials : [..] Mtl_Material;
}

load_mtl :: (path_to_mtl_file: string) -> Mtl_Data {
    file_contents, success := read_entire_file(path_to_mtl_file);
    assert(success, "couldn't open the mtl file");
    defer free(file_contents);

    mtl_data: Mtl_Data;
    current_material: *Mtl_Material = null;

    remainder := file_contents;
    while remainder.count > 0 {
        line: string;
        line, remainder = split_by_newline(remainder);
        line = trim(line);

        if line.count == 0 continue;

        line_type := get_mtl_line_type(line);

        if line_type == {
            case .NEW_MATERIAL;
                mat_name := trim(advance(line, 7));  // skip "newmtl "
                array_add(*mtl_data.all_materials, .{});
                current_material = *mtl_data.all_materials[mtl_data.all_materials.count - 1];
                current_material.name = copy_string(mat_name);

            case .AMBIENT_COLOR;
                if current_material {
                    current_material.ambient_color = parse_vector3(advance(line, 3));  // skip "Ka "
                    current_material.has_ambient_color = true;
                }

            case .DIFFUSE_COLOR;
                if current_material {
                    current_material.diffuse_color = parse_vector3(advance(line, 3));  // skip "Kd "
                    current_material.has_diffuse_color = true;
                }

            case .SPECULAR_COLOR;
                if current_material {
                    current_material.specular_color = parse_vector3(advance(line, 3));  // skip "Ks "
                    current_material.has_specular_color = true;
                }

            case .EMISSIVE_COLOR;
                if current_material {
                    current_material.emissive_color = parse_vector3(advance(line, 3));  // skip "Ke "
                    current_material.has_emissive_color = true;
                }

            case .TRANSMISSION_FILTER;
                if current_material {
                    current_material.transmission_filter = parse_vector3(advance(line, 3));  // skip "Tf "
                    current_material.has_transmission_filter = true;
                }

            case .SPECULAR_EXPONENT;
                if current_material {
                    val, _, _ := string_to_float(trim(advance(line, 3)));  // skip "Ns "
                    current_material.specular_exponent = val;
                    current_material.has_specular_exponent = true;
                }

            case .INDEX_OF_REFRACTION;
                if current_material {
                    val, _, _ := string_to_float(trim(advance(line, 3)));  // skip "Ni "
                    current_material.index_of_refraction = val;
                    current_material.has_index_of_refraction = true;
                }

            case .DISSOLVE;
                if current_material {
                    val, _, _ := string_to_float(trim(advance(line, 2)));  // skip "d "
                    current_material.dissolve = val;
                    current_material.has_dissolve = true;
                }

            case .TRANSPARENCY;
                if current_material {
                    val, _, _ := string_to_float(trim(advance(line, 3)));  // skip "Tr "
                    current_material.dissolve = 1.0 - val;  // convert Tr to d
                    current_material.has_dissolve = true;
                }

            case .ILLUMINATION_MODEL;
                if current_material {
                    val, _, _ := string_to_int(trim(advance(line, 6)));  // skip "illum "
                    current_material.illumination_model = val;
                    current_material.has_illumination_model = true;
                }

            case .MAP_AMBIENT;
                if current_material {
                    current_material.map_ambient = copy_string(trim(advance(line, 7)));  // skip "map_Ka "
                }

            case .MAP_DIFFUSE;
                if current_material {
                    current_material.map_diffuse = copy_string(trim(advance(line, 7)));  // skip "map_Kd "
                }

            case .MAP_SPECULAR;
                if current_material {
                    current_material.map_specular = copy_string(trim(advance(line, 7)));  // skip "map_Ks "
                }

            case .MAP_EMISSIVE;
                if current_material {
                    current_material.map_emissive = copy_string(trim(advance(line, 7)));  // skip "map_Ke "
                }

            case .MAP_SPECULAR_EXPONENT;
                if current_material {
                    current_material.map_specular_exponent = copy_string(trim(advance(line, 7)));  // skip "map_Ns "
                }

            case .MAP_DISSOLVE;
                if current_material {
                    current_material.map_dissolve = copy_string(trim(advance(line, 6)));  // skip "map_d "
                }

            case .MAP_BUMP;
                if current_material {
                    current_material.map_bump = copy_string(trim(advance(line, 9)));  // skip "map_bump "
                }

            case .BUMP;
                if current_material {
                    current_material.map_bump = copy_string(trim(advance(line, 5)));  // skip "bump "
                }

            case .DISPLACEMENT;
                if current_material {
                    current_material.map_displacement = copy_string(trim(advance(line, 5)));  // skip "disp "
                }

            case .DECAL;
                if current_material {
                    current_material.map_decal = copy_string(trim(advance(line, 6)));  // skip "decal "
                }

            case .REFLECTION;
                if current_material {
                    current_material.map_reflection = copy_string(trim(advance(line, 5)));  // skip "refl "
                }

            case .COMMENT;
                // ignore

            case .UNKNOWN;
                // ignore unrecognized lines
        }
    }

    return mtl_data;
}

// utility: find a material by name from parsed mtl data.
find_material_by_name :: (mtl_data: *Mtl_Data, name: string) -> *Mtl_Material {
    for * mtl_data.all_materials {
        if it.name == name return it;
    }
    return null;
}
