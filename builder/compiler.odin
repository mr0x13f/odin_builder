package builder

import "core:mem"
import "core:strings"
import "core:flags"
import "core:path/filepath"
import "core:fmt"
import "core:reflect"

Build_Mode :: enum {
    Executable,
    Test,
    Dynamic_Library,
    Static_Library,
    Object,
    Assembly,
    Llvm_Ir,
}

Build_Mode_Values :: [Build_Mode]string {
    .Executable      = "exe",
    .Test            = "test",
    .Dynamic_Library = "dynamic",
    .Static_Library  = "static",
    .Object          = "object",
    .Assembly        = "assembly",
    .Llvm_Ir         = "llvm-ir",
}

build :: proc {
    build_with_flags,
    build_with_options,
}

build_with_flags :: proc(main_dir: string, out: string, build_mode: Build_Mode = .Executable, flags: ..string) -> (success: bool) {
    // Ensure dir exists
    out_dir := filepath.dir(out, context.temp_allocator)
    mkdir(out_dir)

    // Flags
    out_flag := fmt.tprintf("-out:%s%s", out, get_extension_for_build_mode(build_mode))
    Build_Mode_Values := Build_Mode_Values
    build_mode_flag := fmt.tprintf("-build-mode:%s", Build_Mode_Values[build_mode])

    return call({ "odin", "build", main_dir, out_flag, build_mode_flag }, flags)
}

build_with_options :: proc(main_dir: string, out: string, build_mode: Build_Mode = .Executable, options: Build_Options = {}) -> (success: bool) {
    build_flags := make([dynamic]string, context.temp_allocator)
    options := options

    for field in reflect.struct_fields_zipped(Build_Options) {
        field_value := reflect.struct_field_value(options, field)
        field_ptr := uintptr(&options) + field.offset
        
        // Ignore if value is default (nil/false)
        if mem.check_zero_ptr(rawptr(field_ptr), field.type.size) { continue }

        flag_tag_name, has_flag_tag := reflect.struct_tag_lookup(field.tag, "flag")
        flag_name := has_flag_tag ? flag_tag_name : strings.to_kebab_case(field.name, context.temp_allocator)
        
        switch field.type {
            case type_info_of(bool):
                append(&build_flags, fmt.tprintf("-%s", flag_name))
            case type_info_of(string):
                append(&build_flags, fmt.tprintf("-%s:%s", flag_name, cast(^string)field_ptr))
            case type_info_of(int):
                append(&build_flags, fmt.tprintf("-%s:%i", flag_name, cast(^int)field_ptr))
            case type_info_of([]string):
                append(&build_flags, fmt.tprintf("-%s:%s", flag_name, strings.join((cast(^[]string)field_ptr)^, ",", context.temp_allocator)))
            case type_info_of(map[string]string):
                map_value := (cast(^map[string]string)field_ptr)^
                for key, value in map_value {
                    append(&build_flags, fmt.tprintf("-%s:%s=%s", flag_name, key, value))
                }
            case:
                type_named := field.type.variant.(reflect.Type_Info_Named) or_else
                    panic("Invalid flag field type")
                type_enum := type_named.base.variant.(reflect.Type_Info_Enum) or_else
                    panic("Invalid flag field type")
                option_name_ada := type_enum.names[(cast(^int)field_ptr)^]
                option_name_kebab := strings.to_kebab_case(option_name_ada, context.temp_allocator)
                append(&build_flags, fmt.tprintf("-%s:%s", flag_name, option_name_kebab))
        }
    }

    return build_with_flags(main_dir, out, build_mode, ..build_flags[:])
}

get_extension_for_build_mode :: proc(build_mode: Build_Mode) -> string {
    switch build_mode {
        case .Executable: fallthrough
        case .Test:
            return EXE_EXT
        case .Dynamic_Library:
            return DLL_EXT
        case .Static_Library:
            return LIB_EXT
        case .Object:
            return OBJ_EXT
        case .Assembly:
            return ".s"
        case .Llvm_Ir:
            return ".ll"
    }
    return ""
}
