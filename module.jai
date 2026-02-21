#import "Math";
#import "File";
#import "Basic";
#import "String";

#load "map.jai";

#load "obj.jai";
#load "mtl.jai";

Wavefront_Model :: struct {
    obj_data : Obj_Data;
    mtl_data : Mtl_Data;
    
    base_path : string;  // e.g. "/data/cube"
    directory : string;  // e.g. "/data/"
}

load_wavefront_model :: (base_path: string) -> Wavefront_Model {
    model: Wavefront_Model;
    model.base_path = copy_string(base_path);
    
    // extract directory for resolving relative texture paths later
    // e.g. "/data/cube" -> "/data/"
    last_slash := find_index_from_right(base_path, #char "/");
    if last_slash >= 0 {
        dir: string;
        dir.data = base_path.data;
        dir.count = last_slash + 1;
        model.directory = copy_string(dir);
    } else {
        model.directory = copy_string("");
    }
    
    obj_path := tprint("%.obj", base_path);
    mtl_path := tprint("%.mtl", base_path);
    
    model.obj_data = load_obj(obj_path);
    model.mtl_data = load_mtl(mtl_path);
    
    return model;
}

find_material_for_face :: (model: *Wavefront_Model, face: *Obj_Face) -> *Mtl_Material {
    if face.material_name.count == 0 return null;
    return find_material_by_name(*model.mtl_data, face.material_name);
}

find_material_for_object :: (model: *Wavefront_Model, obj: *Obj_Object) -> *Mtl_Material {
    if obj.faces.count == 0 return null;
    return find_material_for_face(model, *obj.faces[0]);
}

resolve_texture_path :: (model: *Wavefront_Model, relative_path: string) -> string {
    if relative_path.count == 0 return "";
    return tprint("%1%2", model.directory, relative_path);
}

