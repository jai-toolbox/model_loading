// Gameplay surface classification, independent of the material's PBR shading.
Surface_Type :: enum u8 {
    CONCRETE;
    METAL;
    GLASS;
    WOOD;
    TILE;
    DIRT;
}

Surface_Material :: struct {
    surface_type: Surface_Type;
    receives_decals: bool = true;
}

surface_name_contains :: (name: string, word: string) -> bool {
    if name.count < word.count return false;
    for start: 0..name.count - word.count {
        matches := true;
        for offset: 0..word.count - 1 {
            c := name[start + offset];
            if c >= #char "A" && c <= #char "Z" c += 32;
            if c != word[offset] { matches = false; break; }
        }
        if matches return true;
    }
    return false;
}

surface_type_from_name :: (name: string) -> Surface_Type {
    if surface_name_contains(name, "metal") || surface_name_contains(name, "steel") || surface_name_contains(name, "iron") return .METAL;
    if surface_name_contains(name, "glass") return .GLASS;
    if surface_name_contains(name, "wood") || surface_name_contains(name, "timber") return .WOOD;
    if surface_name_contains(name, "tile") || surface_name_contains(name, "ceramic") return .TILE;
    if surface_name_contains(name, "dirt") || surface_name_contains(name, "soil") || surface_name_contains(name, "grass") return .DIRT;
    return .CONCRETE;
}
