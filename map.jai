#import "Basic";
#import "Math";
#import "Hash_Table";

#import "tbx/math";
#import "tbx/geometry";

// Note this file is not a complete implementation of a map loader
// I tested that it works for my own simple .map files and thats it
// I decided not to go further with this because I realized that in 
// the current year for simple maps per triangle collision detection on meshes
// can be viable when for small maps and simple geometry.
// I'm keeping this here because it might be fun to load map files later on.

// I decided to keep the relevant collision detection in here just for simplicity but 
// it's not really part of the map loading, but until we use this code again it's fine to keep it together.

Brush :: struct {
    planes: [..] Plane;
}

Entity :: struct {
    classname: string;
    properties: Table(string, string);
    brushes: [..] Brush;
}

Map :: struct {
    entities: [..] Entity;
}

Player :: struct {
    position: Vector3;
    velocity: Vector3;
    radius: float;
    height: float;
}

Brush_Collision_Result :: struct {
    colliding: bool;
    push_normal: Vector3;
    penetration: float;
}


Coordinate_System :: enum {
    Y_UP;    // opengl, blender default
    Z_UP;    // quake/source engine, 3ds max
}

Parser :: struct {
    data: string;
    pos: int;
    target_coords: Coordinate_System;
    scale: float;  
}

convert_coords :: (v: Vector3, target: Coordinate_System) -> Vector3 {
    if target == .Z_UP {
        // Map files are already Z-up, no conversion needed
        return v;
    } else {
        // Convert from Z-up to Y-up: swap Y and Z
        return Vector3.{ v.x, v.z, v.y };
    }
}

parse_map :: (content: string, target_coords: Coordinate_System = .Y_UP, scale :float = 1) -> Map, bool {
    map: Map;
    parser := Parser.{ data = content, pos = 0, target_coords = target_coords, scale = scale};
    
    while true {
        skip_whitespace_and_comments(*parser);
        
        if parser.pos >= parser.data.count break;
        
        entity, success := parse_entity(*parser);
        if !success {
            log_error("Failed to parse entity");
            return map, false;
        }
        
        array_add(*map.entities, entity);
    }
    
    return map, true;
}

parse_entity :: (parser: *Parser) -> Entity, bool {
    entity: Entity;
    
    skip_whitespace_and_comments(parser);
    
    if !expect_char(parser, #char "{") {
        return entity, false;
    }
    
    while true {
        skip_whitespace_and_comments(parser);
        
        if peek_char(parser) == #char "}" {
            advance(parser);
            break;
        }
        
        if peek_char(parser) == #char "{" {
            brush, success := parse_brush(parser);
            if !success return entity, false;
            array_add(*entity.brushes, brush);
        } else if peek_char(parser) == #char "\"" {
            key, value, success := parse_property(parser);
            if !success return entity, false;
            
            if key == "classname" {
                entity.classname = value;
            }
            table_add(*entity.properties, key, value);
        } else {
            log_error("Unexpected character: %", peek_char(parser));
            return entity, false;
        }
    }
    
    return entity, true;
}

parse_brush :: (parser: *Parser) -> Brush, bool {
    brush: Brush;
    
    if !expect_char(parser, #char "{") {
        return brush, false;
    }
    
    while true {
        skip_whitespace_and_comments(parser);
        
        if peek_char(parser) == #char "}" {
            advance(parser);
            break;
        }
        
        if peek_char(parser) == #char "(" {
            plane, success := parse_face(parser);
            if !success return brush, false;
            array_add(*brush.planes, plane);
        } else {
            log_error("Expected '(' for face definition");
            return brush, false;
        }
    }
    
    return brush, true;
}

parse_face :: (parser: *Parser) -> Plane, bool {
    plane: Plane;
    
    p1, success1 := parse_point(parser);
    if !success1 return plane, false;
    
    skip_whitespace(parser);
    
    p2, success2 := parse_point(parser);
    if !success2 return plane, false;
    
    skip_whitespace(parser);
    
    p3, success3 := parse_point(parser);
    if !success3 return plane, false;
    
    skip_to_newline(parser);
    
    p1 *= parser.scale;
    p2 *= parser.scale;
    p3 *= parser.scale;

    p1 = convert_coords(p1, parser.target_coords);
    p2 = convert_coords(p2, parser.target_coords);
    p3 = convert_coords(p3, parser.target_coords);
    
    edge1 := p2 - p1;
    edge2 := p3 - p1;
    
    // when converting from z-up to y-up, the handedness flips,
    // so we need to reverse the cross product order
    normal: Vector3;
    if parser.target_coords == .Y_UP {
        normal = unit_vector(cross(edge1, edge2));  // flipped order for y-up
    } else {
        normal = unit_vector(cross(edge2, edge1));  // original order for z-up
    }
    
    d := dot(normal, p1);
    
    plane.normal = normal;
    plane.d = d;
    
    return plane, true;
}

parse_point :: (parser: *Parser) -> Vector3, bool {
    point: Vector3;
    
    skip_whitespace(parser);
    
    if !expect_char(parser, #char "(") {
        return point, false;
    }
    
    skip_whitespace(parser);
    x, success_x := parse_float(parser);
    if !success_x return point, false;
    
    skip_whitespace(parser);
    y, success_y := parse_float(parser);
    if !success_y return point, false;
    
    skip_whitespace(parser);
    z, success_z := parse_float(parser);
    if !success_z return point, false;
    
    skip_whitespace(parser);
    
    if !expect_char(parser, #char ")") {
        return point, false;
    }
    
    return .{ x, y, z }, true;
}

parse_property :: (parser: *Parser) -> string, string, bool {
    key, success_key := parse_quoted_string(parser);
    if !success_key return "", "", false;
    
    skip_whitespace(parser);
    
    value, success_value := parse_quoted_string(parser);
    if !success_value return "", "", false;
    
    return key, value, true;
}

parse_quoted_string :: (parser: *Parser) -> string, bool {
    if !expect_char(parser, #char "\"") {
        return "", false;
    }
    
    start := parser.pos;
    
    while parser.pos < parser.data.count && parser.data[parser.pos] != #char "\"" {
        parser.pos += 1;
    }
    
    result := slice(parser.data, start, parser.pos - start);
    
    if !expect_char(parser, #char "\"") {
        return "", false;
    }
    
    return result, true;
}

parse_float :: (parser: *Parser) -> float, bool {
    start := parser.pos;
    
    if parser.pos < parser.data.count && parser.data[parser.pos] == #char "-" {
        parser.pos += 1;
    }
    
    while parser.pos < parser.data.count {
        c := parser.data[parser.pos];
        if (c >= #char "0" && c <= #char "9") || c == #char "." {
            parser.pos += 1;
        } else {
            break;
        }
    }
    
    if parser.pos == start {
        return 0, false;
    }
    
    num_str := slice(parser.data, start, parser.pos - start);
    value, success := string_to_float(num_str);
    
    return value, success;
}


peek_char :: (parser: *Parser) -> u8 {
    if parser.pos >= parser.data.count return 0;
    return parser.data[parser.pos];
}

advance :: (parser: *Parser) {
    if parser.pos < parser.data.count {
        parser.pos += 1;
    }
}

expect_char :: (parser: *Parser, c: u8) -> bool {
    if peek_char(parser) == c {
        advance(parser);
        return true;
    }
    return false;
}

skip_whitespace :: (parser: *Parser) {
    while parser.pos < parser.data.count {
        c := parser.data[parser.pos];
        if c == #char " " || c == #char "\t" || c == #char "\n" || c == #char "\r" {
            parser.pos += 1;
        } else {
            break;
        }
    }
}

skip_whitespace_and_comments :: (parser: *Parser) {
    while parser.pos < parser.data.count {
        skip_whitespace(parser);
        
        if parser.pos + 1 < parser.data.count &&
           parser.data[parser.pos] == #char "/" &&
           parser.data[parser.pos + 1] == #char "/" {
            skip_to_newline(parser);
        } else {
            break;
        }
    }
}

skip_to_newline :: (parser: *Parser) {
    while parser.pos < parser.data.count && parser.data[parser.pos] != #char "\n" {
        parser.pos += 1;
    }
    if parser.pos < parser.data.count {
        parser.pos += 1;
    }
}

slice :: (s: string, start: int, count: int) -> string {
    result: string;
    result.data = s.data + start;
    result.count = count;
    return result;
}

SKIN_WIDTH :: 0.0001;
GRAVITY :: 800.0;
EPSILON__ :: 0.0001; // bad I decided to dodge a name collision because I was being lazy, we should be able to just use EPSILON from math here but idk why I cant right now.

cylinder_plane_distance :: (player: *Player, plane: *Plane) -> float {
    normal := plane.normal;
    
    closest_point := player.position;
    
    // For the horizontal component (XZ plane)
    horizontal_normal := Vector3.{ normal.x, 0, normal.z };
    horizontal_length := length(horizontal_normal);
    
    if horizontal_length > EPSILON__ {
        closest_point.x -= (horizontal_normal.x / horizontal_length) * player.radius;
        closest_point.z -= (horizontal_normal.z / horizontal_length) * player.radius;
    }
    
    // for the vertical component
    if normal.y > 0 {
        closest_point.y -= player.height / 2.0;
    } else if normal.y < 0 {
        closest_point.y += player.height / 2.0;
    }
    
    return dot(normal, closest_point) - plane.d;
}

check_brush_collision :: (player: *Player, brush: *Brush) -> Brush_Collision_Result {
    worst := Brush_Collision_Result.{
        colliding = false,
        push_normal = .{},
        penetration = -FLOAT32_MAX
    };
    
    for * plane : brush.planes {
        dist := cylinder_plane_distance(player, plane);
        
        if dist >= 0 {
            return .{ colliding = false, push_normal = .{}, penetration = 0 };
        }
        
        if dist > worst.penetration {
            worst.penetration = dist;
            worst.push_normal = plane.normal;
            worst.colliding = true;
        }
    }
    
    return worst;
}

resolve_penetration :: (player: *Player, hit: *Brush_Collision_Result) {
    if hit.colliding {
        player.position += hit.push_normal * (-hit.penetration + SKIN_WIDTH);
    }
}

update_player :: (player: *Player, map: *Map, dt: float) {
    MAX_ITERATIONS :: 4;
    for iteration : 0..MAX_ITERATIONS-1 {
        any_collision := false;
        
        for * entity : map.entities {
            for * brush : entity.brushes {
                hit := check_brush_collision(player, brush);
                
                if hit.colliding {
                    resolve_penetration(player, *hit);
                    adjust_velocity(player, hit.push_normal);
                    any_collision = true;
                }
            }
        }
        
        if !any_collision break;
    }
}

adjust_velocity :: (player: *Player, normal: Vector3) {
    into_wall := dot(player.velocity, normal);
    
    if into_wall < 0 {
        player.velocity -= normal * into_wall;
    }
}

is_on_ground :: (player: *Player, map: *Map) -> bool {
    GROUND_THRESHOLD :: 0.1;
    SLOPE_THRESHOLD :: 0.7;
    
    for * entity : map.entities {
        for * brush : entity.brushes {
            for * plane : brush.planes {
                if plane.normal.y > SLOPE_THRESHOLD {
                    dist := cylinder_plane_distance(player, plane);
                    if dist > -GROUND_THRESHOLD && dist < GROUND_THRESHOLD {
                        return true;
                    }
                }
            }
        }
    }
    
    return false;
}


// represents a list of vertices (wound in order)
Polygon :: struct {
    vertices: [..] Vector3;
}

WORLD_BOUNDS :: 4096.0; // I read online that this is how they create meshes from brushes.

make_huge_polygon_for_plane :: (plane: Plane) -> Polygon { // assumes y up coordinate system.
    // create a huge polygon on this plane
    // first, find a basis for the plane
    
    poly: Polygon;
    
    up: Vector3;
    if abs(plane.normal.y) < 0.9 {  
        up = .{ 0, 1, 0 };  // Was { 0, 0, 1 }
    } else {
        up = .{ 1, 0, 0 };
    }
    
    right := unit_vector(cross(up, plane.normal));
    forward := unit_vector(cross(plane.normal, right));
    
    right *= WORLD_BOUNDS * 2;
    forward *= WORLD_BOUNDS * 2;
    
    center := plane.normal * plane.d;
    
    // quad vertices (counter-clockwise when looking at front face)
    array_add(*poly.vertices, center - right - forward);
    array_add(*poly.vertices, center + right - forward);
    array_add(*poly.vertices, center + right + forward);
    array_add(*poly.vertices, center - right + forward);
    
    return poly;
}

classify_point :: (point: Vector3, plane: Plane) -> float {
    return dot(plane.normal, point) - plane.d;
}

// keeps the back side (negative side)
clip_polygon :: (poly: *Polygon, plane: Plane) -> bool {
    if poly.vertices.count < 3 return false;
    
    new_vertices: [..] Vector3;
    
    for i : 0..poly.vertices.count-1 {
        j := (i + 1) % poly.vertices.count;
        
        vi := poly.vertices[i];
        vj := poly.vertices[j];
        
        di := classify_point(vi, plane);
        dj := classify_point(vj, plane);
        
        // Point i is on back side or on plane (keep it)
        if di <= EPSILON__ {
            array_add(*new_vertices, vi);
        }
        
        // Edge crosses the plane
        if (di > EPSILON__ && dj < -EPSILON__) || (di < -EPSILON__ && dj > EPSILON__) {
            // Compute intersection point
            t := di / (di - dj);
            intersection := vi + (vj - vi) * t;
            array_add(*new_vertices, intersection);
        }
    }
    
    array_reset(*poly.vertices);
    for v : new_vertices {
        array_add(*poly.vertices, v);
    }
    array_free(new_vertices);
    
    return poly.vertices.count >= 3;
}

free_polygon :: (poly: *Polygon) {
    array_free(poly.vertices);
}


brush_to_mesh :: (brush: *Brush) -> Indexed_Triangle_Positions {
    mesh: Indexed_Triangle_Positions;
    
    // for each face plane, create a polygon and clip it against all other planes
    for face_idx : 0..brush.planes.count-1 {
        face_plane := brush.planes[face_idx];
        
        poly := make_huge_polygon_for_plane(face_plane);
        
        // clip against all other planes
        valid := true;
        for clip_idx : 0..brush.planes.count-1 {
            if clip_idx == face_idx continue;
            
            clip_plane := brush.planes[clip_idx];
            
            // we want to keep the part that's on the inside (back) of each clip plane
            if !clip_polygon(*poly, clip_plane) {
                valid = false;
                break;
            }
        }
        
        if valid && poly.vertices.count >= 3 {
            add_polygon_to_mesh(*mesh, *poly);
        }
        
        free_polygon(*poly);
    }
    
    return mesh;
}

add_polygon_to_mesh :: (mesh: *Indexed_Triangle_Positions, poly: *Polygon) {
    if poly.vertices.count < 3 return;
    
    // fan triangulation from first vertex
    base_index := cast(u32) mesh.positions.count;
    
    for v : poly.vertices {
        array_add(*mesh.positions, v);
    }
    
    // create triangles (fan from vertex 0)
    for i : 1..poly.vertices.count-2 {
        array_add(*mesh.indices, base_index);
        array_add(*mesh.indices, base_index + cast(u32) i);
        array_add(*mesh.indices, base_index + cast(u32) (i + 1));
    }
}


map_to_mesh_deduplicated :: (map: *Map) -> Indexed_Triangle_Positions {
    mesh: Indexed_Triangle_Positions;
    vertex_map: Table(u64, u32);
    
    hash_vertex :: (v: Vector3) -> u64 {
        SCALE :: 1000.0;
        x := cast(s64) (v.x * SCALE);
        y := cast(s64) (v.y * SCALE);
        z := cast(s64) (v.z * SCALE);
        
        hx := cast,no_check(u64) x;
        hy := cast,no_check(u64) y;
        hz := cast,no_check(u64) z;
        
        h := hx;
        h = h * 31 + hy;
        h = h * 31 + hz;
        return h;
    }
    
    get_or_add_vertex :: (mesh: *Indexed_Triangle_Positions, 
                          vertex_map: *Table(u64, u32), 
                          v: Vector3) -> u32 {
        hash := hash_vertex(v);
        
        existing := table_find_pointer(vertex_map, hash);
        if existing {
            return <<existing;
        }
        
        new_index := cast(u32) mesh.positions.count;
        array_add(*mesh.positions, v);
        table_add(vertex_map, hash, new_index);
        return new_index;
    }
    
    for * entity : map.entities {
        for * brush : entity.brushes {
            brush_mesh := brush_to_mesh(brush);
            
            for i : 0..brush_mesh.indices.count-1 {
                old_idx := brush_mesh.indices[i];
                v := brush_mesh.positions[old_idx];
                new_idx := get_or_add_vertex(*mesh, *vertex_map, v);
                array_add(*mesh.indices, new_idx);
            }
            
            array_free(brush_mesh.positions);
            array_free(brush_mesh.indices);
        }
    }
    
    deinit(*vertex_map);
    return mesh;
}

map_to_mesh :: (map: *Map) -> Indexed_Triangle_Positions {
    mesh: Indexed_Triangle_Positions;
    
    for * entity : map.entities {
        for * brush : entity.brushes {
            brush_mesh := brush_to_mesh(brush);
            
            base_index := cast(u32) mesh.positions.count;
            
            for pos : brush_mesh.positions {
                array_add(*mesh.positions, pos);
            }
            
            for idx : brush_mesh.indices {
                array_add(*mesh.indices, base_index + idx);
            }
            
            array_free(brush_mesh.positions);
            array_free(brush_mesh.indices);
        }
    }
    
    return mesh;
}




usage :: () {
    map_content := #string DONE
// entity 0
{
"mapversion" "220"
"classname" "worldspawn"
// brush 0
{
( -64 -64 -16 ) ( -64 -63 -16 ) ( -64 -64 -15 ) __TB_empty [ 0 -1 0 0 ] [ 0 0 -1 0 ] 0 0.5 0.5
( -64 -64 -16 ) ( -64 -64 -15 ) ( -63 -64 -16 ) __TB_empty [ 1 0 0 0 ] [ 0 0 -1 0 ] 0 0.5 0.5
( -64 -64 -16 ) ( -63 -64 -16 ) ( -64 -63 -16 ) __TB_empty [ -1 0 0 0 ] [ 0 -1 0 0 ] 0 0.5 0.5
( 64 64 16 ) ( 64 65 16 ) ( 65 64 16 ) __TB_empty [ 1 0 0 0 ] [ 0 -1 0 0 ] 0 0.5 0.5
( 64 64 16 ) ( 65 64 16 ) ( 64 64 17 ) __TB_empty [ -1 0 0 0 ] [ 0 0 -1 0 ] 0 0.5 0.5
( 64 64 16 ) ( 64 64 17 ) ( 64 65 16 ) __TB_empty [ 0 1 0 0 ] [ 0 0 -1 0 ] 0 0.5 0.5
}
}
DONE;

    map, success := parse_map(map_content);
    
    if !success {
        print("Failed to parse map!\n");
        return;
    }
    
    print("Parsed % entities\n", map.entities.count);

    
    for * entity : map.entities {
        print("  Entity: %\n", entity.classname);
        print("    Brushes: %\n", entity.brushes.count);
    }

    
    // Convert to mesh
    mesh := map_to_mesh_deduplicated(*map);
    
    print("\nGenerated mesh:\n");
    print("  Vertices: %\n", mesh.positions.count);
    print("  Triangles: %\n", mesh.indices.count / 3);
    
    print("\nVertices:\n");
    for pos, i : mesh.positions {
        print("  [%]: (%, %, %)\n", i, pos.x, pos.y, pos.z);
    }
    
    print("\nTriangles:\n");
    for i : 0..mesh.indices.count/3-1 {
        i0 := mesh.indices[i*3 + 0];
        i1 := mesh.indices[i*3 + 1];
        i2 := mesh.indices[i*3 + 2];
        print("  [%]: %, %, %\n", i, i0, i1, i2);
    }

    
    player := Player.{
        position = .{ 0, 0, 100 },
        velocity = .{ 10, 5, 0 },
        radius = 16,
        height = 56
    };
    
    print("\nSimulating player...\n");
    
    dt :: 1.0 / 60.0;
    for frame : 0..120 {
        update_player(*player, *map, dt);
        
        if frame % 20 == 0 {
            grounded := is_on_ground(*player, *map);
            print("Frame %: pos=(%, %, %) grounded=%\n",
                  frame,
                  player.position.x, player.position.y, player.position.z,
                  grounded);
        }
    }
}
