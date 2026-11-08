/*
Effect textures need HDR color and opacity in an ordinary image file. These
procedures read and write uncompressed scanline OpenEXR images with float
R/G/B/A channels. Other OpenEXR compression and channel types are rejected.
The byte-writing code follows the existing RGB writer in tbx/sky.
*/
#scope_module
#import "Basic";
#import "Math";
#import "File";
#scope_export

Float_Image :: struct {
    width, height: s32;
    pixels: [..] Vector4;
}

free_float_image :: (image: *Float_Image) {
    array_free(image.pixels);
    image.* = .{};
}

write_open_exr :: (path: string, width: s32, height: s32, pixels: [] Vector4, flip_vertical: bool = false) -> bool {
    if width <= 0 || height <= 0 || pixels.count != cast(s64) width*height return false;
    header, value: [..] u8;
    defer array_free(header);
    defer array_free(value);
    exr_u32(*header, 20000630);
    exr_u32(*header, 2);
    for channel: string.["A", "B", "G", "R"] {
        exr_cstring(*value, channel);
        exr_u32(*value, 2); // FLOAT
        exr_u32(*value, 0); // pLinear and reserved bytes
        exr_u32(*value, 1); exr_u32(*value, 1);
    }
    array_add(*value, 0);
    exr_attribute(*header, "channels", "chlist", value);
    array_reset(*value); array_add(*value, 0);
    exr_attribute(*header, "compression", "compression", value);
    array_reset(*value);
    exr_u32(*value, 0); exr_u32(*value, 0);
    exr_u32(*value, cast(u32) (width-1)); exr_u32(*value, cast(u32) (height-1));
    exr_attribute(*header, "dataWindow", "box2i", value);
    exr_attribute(*header, "displayWindow", "box2i", value);
    array_reset(*value); array_add(*value, 0);
    exr_attribute(*header, "lineOrder", "lineOrder", value);
    array_reset(*value); exr_float(*value, 1);
    exr_attribute(*header, "pixelAspectRatio", "float", value);
    array_reset(*value); exr_float(*value, 0); exr_float(*value, 0);
    exr_attribute(*header, "screenWindowCenter", "v2f", value);
    array_reset(*value); exr_float(*value, 1);
    exr_attribute(*header, "screenWindowWidth", "float", value);
    array_add(*header, 0);
    row_bytes := cast(s64) width*16;
    if row_bytes > 0x7fffffff return false;
    offset := cast(u64) header.count+cast(u64) height*8;
    for y: 0..height-1 {
        exr_u64(*header, offset);
        offset += cast(u64) row_bytes+8;
    }
    file, ok := file_open(path, for_writing = true, keep_existing_content = false);
    if !ok return false;
    defer file_close(*file);
    if !file_write(*file, header.data, header.count) return false;
    array_reserve(*value, row_bytes+8);
    for y: 0..height-1 {
        array_reset_keeping_memory(*value);
        exr_u32(*value, xx y); exr_u32(*value, xx row_bytes);
        source_y := ifx flip_vertical then height-1-y else y;
        for channel: int.[3, 2, 1, 0] for x: 0..width-1
            exr_float(*value, pixels[source_y*width+x].component[channel]);
        if !file_write(*file, value.data, value.count) return false;
    }
    return true;
}

read_open_exr :: (path: string, maximum_bytes: s64 = 2*1024*1024*1024, flip_vertical: bool = false) -> (Float_Image, bool) {
    data, ok := read_entire_file(path);
    if !ok return .{}, false;
    defer free(data);
    if data.count < 16 || exr_read_u32(data, 0) != 20000630 || exr_read_u32(data, 4) != 2 return .{}, false;
    cursor: s64 = 8;
    width, height: s32;
    channels: [4] s32;
    channel_count: int;
    uncompressed, window, rgba: bool;
    while cursor < data.count && data[cursor] != 0 {
        name, name_ok := exr_read_cstring(data, *cursor);
        type, type_ok := exr_read_cstring(data, *cursor);
        if !name_ok || !type_ok || cursor+4 > data.count return .{}, false;
        size := cast(s64) exr_read_u32(data, cursor); cursor += 4;
        end := cursor+size;
        if end > data.count return .{}, false;
        if name == "compression" uncompressed = type == "compression" && size == 1 && data[cursor] == 0;
        if name == "dataWindow" && type == "box2i" && size == 16 {
            if exr_read_u32(data, cursor) != 0 || exr_read_u32(data, cursor+4) != 0 return .{}, false;
            w := cast(u64) exr_read_u32(data, cursor+8)+1;
            h := cast(u64) exr_read_u32(data, cursor+12)+1;
            if w > 65536 || h > 65536 return .{}, false;
            width = xx w; height = xx h; window = true;
        }
        if name == "channels" && type == "chlist" {
            position := cursor;
            mask: u32;
            while position < end && data[position] != 0 {
                channel, valid := exr_read_cstring(data, *position);
                if !valid || position+16 > end || channel_count >= 4 return .{}, false;
                index: s32 = -1;
                if channel == "R" index = 0;
                if channel == "G" index = 1;
                if channel == "B" index = 2;
                if channel == "A" index = 3;
                if index < 0 || (mask & (cast(u32) 1 << index)) != 0 return .{}, false;
                if exr_read_u32(data, position) != 2 || exr_read_u32(data, position+8) != 1 || exr_read_u32(data, position+12) != 1 return .{}, false;
                channels[channel_count] = index; channel_count += 1;
                mask |= cast(u32) 1 << index;
                position += 16;
            }
            rgba = mask == 15 && channel_count == 4 && position == end-1 && data[position] == 0;
        }
        cursor = end;
    }
    if !uncompressed || !window || !rgba || cursor >= data.count return .{}, false;
    cursor += 1;
    bytes := cast(s64) width*height*16;
    if bytes <= 0 || maximum_bytes <= 0 || bytes > maximum_bytes || cursor+cast(s64) height*8 > data.count return .{}, false;
    if bytes+cast(s64) height*16 > data.count-cursor return .{}, false;
    image: Float_Image;
    image.width = width; image.height = height;
    array_resize(*image.pixels, cast(s64) width*height);
    success := false;
    defer if !success free_float_image(*image);
    seen: [..] bool; array_resize(*seen, height); defer array_free(seen);
    for row: 0..height-1 {
        raw := exr_read_u64(data, cursor+row*8);
        if raw > cast(u64) data.count || raw+8+cast(u64) width*16 > cast(u64) data.count return .{}, false;
        offset := cast(s64) raw;
        y := exr_read_u32(data, offset);
        if y >= cast(u32) height || seen[y] || exr_read_u32(data, offset+4) != cast(u32) width*16 return .{}, false;
        seen[y] = true; offset += 8;
        destination_y: s64 = cast(s64) y;
        if flip_vertical destination_y = height-1-destination_y;
        for channel: 0..3 for x: 0..width-1 {
            bits := exr_read_u32(data, offset); offset += 4;
            image.pixels[destination_y*width+x].component[channels[channel]] = (.*) cast(*float32) *bits;
        }
    }
    success = true;
    return image, true;
}

#scope_module
exr_u32 :: (dest: *[..] u8, value: u32) {
    for shift: 0..3 array_add(dest, cast(u8) ((value >> cast(u32) (shift*8)) & 255));
}
exr_u64 :: (dest: *[..] u8, value: u64) {
    for shift: 0..7 array_add(dest, cast(u8) ((value >> cast(u64) (shift*8)) & 255));
}
exr_float :: (dest: *[..] u8, value: float32) { exr_u32(dest, (.*) cast(*u32) *value); }
exr_cstring :: (dest: *[..] u8, value: string) { for byte: value array_add(dest, byte); array_add(dest, 0); }
exr_attribute :: (dest: *[..] u8, name: string, type: string, value: [] u8) {
    exr_cstring(dest, name); exr_cstring(dest, type); exr_u32(dest, xx value.count); array_add(dest, ..value);
}
exr_read_u32 :: (data: string, offset: s64) -> u32 {
    result: u32;
    for i: 0..3 {
        byte: u32 = cast(u32) data[offset+i];
        result |= byte << cast(u32) (i*8);
    }
    return result;
}
exr_read_u64 :: (data: string, offset: s64) -> u64 {
    result: u64;
    for i: 0..7 {
        byte: u64 = cast(u64) data[offset+i];
        result |= byte << cast(u64) (i*8);
    }
    return result;
}
exr_read_cstring :: (data: string, cursor: *s64) -> (string, bool) {
    start := cursor.*;
    while cursor.* < data.count && data[cursor.*] != 0 cursor.* += 1;
    if cursor.* >= data.count return "", false;
    result: string = .{cursor.*-start, data.data+start};
    cursor.* += 1;
    return result, true;
}
