package builder

import "core:mem"
import "core:strings"
import "core:path/filepath"
import "core:fmt"
import "core:reflect"

Odin_Build_Mode :: enum {
    Executable,
    Test,
    Dynamic_Library,
    Static_Library,
    Object,
    Assembly,
    Llvm_Ir,
}

Build_Mode_Values :: [Odin_Build_Mode]string {
    .Executable      = "exe",
    .Test            = "test",
    .Dynamic_Library = "dynamic",
    .Static_Library  = "static",
    .Object          = "object",
    .Assembly        = "assembly",
    .Llvm_Ir         = "llvm-ir",
}

odin_build :: proc {
    odin_build_with_flags,
    odin_build_with_options,
}

odin_build_with_flags :: proc(
    main_dir: string,
    out_without_ext: string,
    build_mode: Odin_Build_Mode = .Executable,
    target: Odin_Build_Targets = .Native,
    flags: ..string
) -> (success: bool) {
    // Ensure dir exists
    out_dir := filepath.dir(out_without_ext)
    mkdir(out_dir)

    // Flags
    out_flag := fmt.tprintf("-out:%s%s", out_without_ext, get_extension_for_build_mode(build_mode, target))
    Build_Mode_Values := Build_Mode_Values
    build_mode_flag := fmt.tprintf("-build-mode:%s", Build_Mode_Values[build_mode])
    
    target_flag: string
    if (target != .Native) {
        target_name_ada := reflect.enum_name_from_value(target) or_else panic("Bad target value")
        target_flag = fmt.tprintf("-target:%s", strings.to_snake_case(target_name_ada, context.temp_allocator))
    }

    return call({ "odin", "build", main_dir, out_flag, build_mode_flag, target_flag }, flags)
}

odin_build_with_options :: proc(
    main_dir: string, 
    out_without_ext: string,
    build_mode: Odin_Build_Mode = .Executable,
    target: Odin_Build_Targets = .Native,
    options: Odin_Build_Options = {}
) -> (success: bool) {
    build_flags := make([dynamic]string, context.temp_allocator)
    options := options

    for field in reflect.struct_fields_zipped(Odin_Build_Options) {
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
                append(&build_flags, fmt.tprintf("-%s:%s", flag_name, (cast(^string)field_ptr)^))
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

    return odin_build_with_flags(main_dir, out_without_ext, build_mode, target, ..build_flags[:])
}

get_extension_for_build_mode :: proc(build_mode: Odin_Build_Mode, target: Odin_Build_Targets) -> string {
    extensions: Extensions

    switch target {
        case .Native:
            extensions = NATIVE_EXTENSIONS
        case .Darwin_Amd64, .Darwin_Arm64:
            extensions = MACOS_EXTENSIONS
        case .Windows_I386, .Windows_Amd64, .Freestanding_Amd64_Win64:
            extensions = WINDOWS_EXTENSIONS
        case .Freestanding_Amd64_Mingw:
            extensions = MINGW_EXTENSIONS
        case .Freestanding_Wasm32, .Wasi_Wasm32, .Js_Wasm32, .Orca_Wasm32: fallthrough
        case .Freestanding_Wasm64p32, .Js_Wasm64p32, .Wasi_Wasm64p32:
            extensions = WASM_EXTENSIONS
        case .Linux_I386, .Linux_Amd64, .Linux_Arm64, .Linux_Arm32, .Linux_Riscv64: fallthrough
        case .Freebsd_I386, .Freebsd_Amd64, .Freebsd_Arm64, .Netbsd_Amd64, .Netbsd_Arm64, .Openbsd_Amd64: fallthrough
        case .Freestanding_Amd64_Sysv, .Freestanding_Arm64, .Freestanding_Arm32, .Freestanding_Riscv64:
            extensions = LINUX_EXTENSIONS
    }

    switch build_mode {
        case .Executable: fallthrough
        case .Test:
            return extensions.executable
        case .Dynamic_Library:
            return extensions.dynamic_library
        case .Static_Library:
            return extensions.static_library
        case .Object:
            return extensions.object
        case .Assembly:
            return EXTENSION_ASSEMBLY
        case .Llvm_Ir:
            return EXTENSION_LLVM_IR
    }
    return ""
}
