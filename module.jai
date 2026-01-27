#import "Math";
#import "File";
#import "Basic";
#import "String";

Obj_Line_Type :: enum {
    UNKNOWN;
    VERTEX;
    TEXTURE_COORDINATE;
    NORMAL;
    FACE; // holds indices into the above types
    OBJECT; // if you had two disjoint cubes each would probably be an object.
    COMMENT;
}

get_line_type :: (line: string) -> Obj_Line_Type {

    if line.count == 0 return .UNKNOWN;
    
    if line[0] == #char "#" return .COMMENT;
    
    // order matters here we check longer prefixes first
    // to avoid "vt" or "vn" matching as "v"
    if begins_with(line, "vt ") return .TEXTURE_COORDINATE;
    if begins_with(line, "vn ") return .NORMAL;
    if begins_with(line, "v ")  return .VERTEX;
    if begins_with(line, "f ")  return .FACE;
    if begins_with(line, "o ")  return .OBJECT;
    
    return .UNKNOWN;
}


/*

 Note that we only have basic obj support, you can see everything that obj can theoretically do here:

 https://paulbourke.net/dataformats/obj/

 But we will only do a small subset that gets us by.

*/

Obj_Object :: struct {
    faces : [..] Obj_Face;
}

Obj_Face :: struct {
    face_vertices : [..] Obj_Face_Vertex;
}

Obj_Face_Vertex :: struct {
    position_index := -1;
    texture_coordinate_index := -1;
    normal_index := -1;
}

// this is a minimal piece of data representing an obj file, but now it's in memory so we can do stuff to it.
Obj_Data :: struct {
    all_positions : [..] Vector3;
    all_texture_coordinates : [..] Vector2;
    all_normals : [..] Vector3;
    // the objects store indices into the above arrays, use them to reconstruct the objects.
    all_objects : [..] Obj_Object;
}

load_obj :: (path_to_obj_file: string) -> Obj_Data {
    file_contents, success := read_entire_file(path_to_obj_file);
    assert(success, "couldn't open the file");
    defer free(file_contents);

    obj_data: Obj_Data;
    current_object: *Obj_Object = null;

    remainder := file_contents;
    while remainder.count > 0 {
        line: string;
        line, remainder = split_by_newline(remainder);
        line = trim(line);
        
        if line.count == 0 continue;

        line_type := get_line_type(line);

        if line_type == {
            case .VERTEX;
                vec := parse_vector3(advance(line, 2));  // skip "v "
                array_add(*obj_data.all_positions, vec);

            case .TEXTURE_COORDINATE;
                vec := parse_vector2(advance(line, 3));  // skip "vt "
                array_add(*obj_data.all_texture_coordinates, vec);

            case .NORMAL;
                vec := parse_vector3(advance(line, 3));  // skip "vn "
                array_add(*obj_data.all_normals, vec);

            case .OBJECT;
                array_add(*obj_data.all_objects, .{});
                current_object = *obj_data.all_objects[obj_data.all_objects.count - 1];

            case .FACE;
                // create default object if none exists yet, this allows obj files that have no
                // object lines in them to still have a default object.
                if current_object == null {
                    array_add(*obj_data.all_objects, .{});
                    current_object = *obj_data.all_objects[obj_data.all_objects.count - 1];
                }
                
                face := parse_face(advance(line, 2));  // skip "f "
                array_add(*current_object.faces, face);

            case .COMMENT;
                // ignore

            case .UNKNOWN;
                // ignore (mtllib, usemtl, s, g, etc.), will try and add mtl later.
        }
    }

    return obj_data;
}

// helper functions used in the above.

split_by_newline :: (s: string) -> (line: string, remainder: string) {
    for i: 0..s.count-1 {
        if s[i] == #char "\n" {
            line: string;
            line.data = s.data;
            line.count = i;
            
            remainder: string;
            remainder.data = s.data + i + 1;
            remainder.count = s.count - i - 1;
            
            return line, remainder;
        }
    }
    return s, "";
}

parse_vector3 :: (s: string) -> Vector3 {
    result: Vector3;
    remainder := trim(s);
    
    result.x, _, remainder = string_to_float(remainder);
    remainder = trim(remainder);
    result.y, _, remainder = string_to_float(remainder);
    remainder = trim(remainder);
    result.z, _, remainder = string_to_float(remainder);
    
    return result;
}

parse_vector2 :: (s: string) -> Vector2 {
    result: Vector2;
    remainder := trim(s);
    
    result.x, _, remainder = string_to_float(remainder);
    remainder = trim(remainder);
    result.y, _, remainder = string_to_float(remainder);
    
    return result;
}

parse_face :: (s: string) -> Obj_Face {
    face: Obj_Face;
    remainder := trim(s);
    
    while remainder.count > 0 {
        // get the next vertex token (e.g., "1/2/3" or "1//3" or "1")
        token: string;
        space_idx := find_index_from_left(remainder, #char " ");
        
        if space_idx < 0 {
            token = remainder;
            remainder = "";
        } else {
            token.data = remainder.data;
            token.count = space_idx;
            remainder = trim(advance(remainder, space_idx + 1));
        }
        
        if token.count > 0 {
            face_vertex := parse_face_vertex(token);
            array_add(*face.face_vertices, face_vertex);
        }
    }
    
    return face;
}

parse_face_vertex :: (s: string) -> Obj_Face_Vertex {
    // formats: "v", "v/vt", "v/vt/vn", "v//vn"
    // OBJ indices are 1-based, convert to 0-based
    
    fv: Obj_Face_Vertex;
    remainder := s;
    
    // position index (always present)
    pos_idx, success, remainder_ := string_to_int(remainder);
    remainder = remainder_;
    if success then fv.position_index = pos_idx - 1;
    
    // check for first slash
    if remainder.count > 0 && remainder[0] == #char "/" {
        remainder = advance(remainder, 1);
        
        // texture coordinate index (may be empty)
        if remainder.count > 0 && remainder[0] != #char "/" {
            tex_idx: int;
            tex_idx, success, remainder = string_to_int(remainder);
            if success then fv.texture_coordinate_index = tex_idx - 1;
        }
        
        // check for second slash
        if remainder.count > 0 && remainder[0] == #char "/" {
            remainder = advance(remainder, 1);
            
            // normal index
            norm_idx: int;
            norm_idx, success, remainder = string_to_int(remainder);
            if success then fv.normal_index = norm_idx - 1;
        }
    }
    
    return fv;
}
