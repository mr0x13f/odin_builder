#+feature dynamic-literals
package tools

import "core:io"
import "core:strings"
import "core:fmt"
import "core:path/filepath"
import "core:os/os2"

// $ odin run tools/generate_build_options.odin -file


// Tool to generate the Build_Options struct used in builder/compiler.odin,
// based on the output of $ odin build --help
// Will output to builder/build_options.odin


rename_flags := map[string]string {
    "o"                = "optimization",
    "custom_attribute" = "custom_attributes",
    "collection"       = "collections",
}

replace_flag_type := map[string]string {
    "custom_attribute" = "[]string",
    "target_features"  = "[]string",
}

exclude_flags := map[string]bool {
    "out"        = true,
    "build_mode" = true,
    "lld"        = true,
    "radlink"    = true,
}

usage_lines: []string
lines_read: int
reached_end: bool

main :: proc() {

    // Read usage
    command := []string { "odin", "build", "--help" }
    _, usage, _ := os2.process_exec({ command = command, }, context.allocator) or_else
        panic("Failed to start odin")
    usage_lines = strings.split_lines(string(usage))

    // Generate code
    build_options_struct_builder := strings.builder_make()
    other_types_builder := strings.builder_make()

    fmt.sbprintln(&build_options_struct_builder, "// Generated with tools/generate_build_options.odin")
    fmt.sbprintln(&build_options_struct_builder)
    fmt.sbprintln(&build_options_struct_builder)
    fmt.sbprintln(&build_options_struct_builder, "// Odin build options, corresponds to usage of `odin build`")
    fmt.sbprintln(&build_options_struct_builder, "Build_Options :: struct {")
    fmt.sbprintln(&build_options_struct_builder)
    skip_lines_until_after("\tFlags")
    skip_lines_until_prefix("\t-")
    for !reached_end {
        line := consume_line()
        defer skip_lines_until_prefix("\t-")

        // Name
        flag_name := strings.trim_left_space(line)[1:]
        colon_idx := strings.index(flag_name, ":")
        flag_type := ""
        if colon_idx != -1 {
            flag_type = flag_name[colon_idx+1:]
            flag_name = flag_name[:colon_idx]
        }
        field_name := strings.to_snake_case(flag_name, context.temp_allocator)
        custom_field_name := false

        // Type
        field_type: string
        is_enum := false
        switch flag_type {
            case "":
                field_type = "bool"
            case "<integer>":
                field_type = "int"
            case "<string>": fallthrough
            case "<filename>": fallthrough
            case "<filepath>":
                field_type = "string"
            case "<comma-separated-strings>":
                field_type = "[]string"
            case "<name>=<value>": fallthrough
            case "<name>=<filepath>":
                field_type = "map[string]string"
        }

        if field_name in exclude_flags { continue }
        if field_name in replace_flag_type {
            field_type = replace_flag_type[field_name] }
        if field_name in rename_flags {
            custom_field_name = true
            field_name = rename_flags[field_name]
        }

        // Write comments
        ENUM_OPTIONS_PREFIXES :: []string { "\t\tAvailable ", "\t\tChoices:" }
        for comment in consume_until_prefix_or_empty(..ENUM_OPTIONS_PREFIXES) {
            fmt.sbprintfln(&build_options_struct_builder, "    // %s", comment[2:])
        }

        // Enum
        if has_any_prefix(peek_line(), ..ENUM_OPTIONS_PREFIXES) {
            consume_line()
            enum_name_snake_case := fmt.tprintf("Build_%s_Options", field_name)
            enum_name := strings.to_ada_case(enum_name_snake_case, context.temp_allocator) or_else panic("Mem error")
            field_type = enum_name
            is_enum = true

            // Write enum definition
            fmt.sbprintfln(&other_types_builder, "%s :: enum {{", enum_name)
            fmt.sbprintln(&other_types_builder, "    Default,")
            for option_line in consume_until_prefix_or_empty("\t-") {
                if strings.has_prefix(option_line, "\t\tThe default is") {
                    fmt.sbprintfln(&build_options_struct_builder, "    // %s", strings.trim_left_space(option_line))
                    continue
                }
                option_name_kebab := strings.trim_left_space(option_line)
                if option_name_kebab[0] == '-' && strings.has_prefix(option_name_kebab[1:], flag_name) {
                    option_name_kebab = option_name_kebab[len(flag_name)+2:]
                }
                if strings.has_prefix(option_name_kebab, "default") { continue } // Already added as nil option
                first_space := strings.index(option_name_kebab, " ")
                if first_space != -1 {
                    comment := strings.trim_left_space(option_name_kebab[first_space:])
                    fmt.sbprintfln(&other_types_builder, "    // %s", comment)
                    option_name_kebab = option_name_kebab[:first_space]
                }
                option_name_ada := strings.to_ada_case(option_name_kebab, context.temp_allocator)
                fmt.sbprintfln(&other_types_builder, "    %s,", option_name_ada)
            }
            fmt.sbprintln(&other_types_builder, "}")
            fmt.sbprintln(&other_types_builder)
        }

        // Write field
        fmt.sbprintf(&build_options_struct_builder, "    %s: %s", field_name, field_type)
        if custom_field_name {
            fmt.sbprintf(&build_options_struct_builder, " `flag:\"%s\"`", flag_name)
        }
        fmt.sbprintln(&build_options_struct_builder, ",")
        fmt.sbprintln(&build_options_struct_builder)
    }
    fmt.sbprintln(&build_options_struct_builder, "}")
    fmt.sbprintln(&build_options_struct_builder)

    // Write output
    out_path := "builder/build_options.odin"
    out_path_abs := filepath.join({ filepath.dir(os2.args[0]), out_path  })
    out_file := os2.open(out_path_abs, { .Create, .Write, .Trunc }) or_else
        panic("Failed to open output file")
    defer os2.close(out_file)
    out_writer := os2.to_writer(out_file)

    fmt.wprintln(out_writer, "package builder")
    fmt.wprintln(out_writer)
    fmt.wprint(out_writer, strings.to_string(build_options_struct_builder))
    fmt.wprint(out_writer, strings.to_string(other_types_builder))

    fmt.printfln("Successfully wrote to %s", out_path)

}

peek_line :: proc() -> string {
    return usage_lines[lines_read]
}

consume_line :: proc() -> (line: string) {
    line = usage_lines[lines_read]
    lines_read += 1
    reached_end = lines_read >= len(usage_lines)
    return
}

skip_lines_until_after :: proc(line: string) {
    for !reached_end && consume_line() != line { }
}

skip_lines_until_prefix :: proc(prefix: string) {
    for !reached_end && !strings.has_prefix(peek_line(), prefix) {
        consume_line()
    }
}

consume_until_prefix_or_empty :: proc(prefixes: ..string) -> []string {
    start_idx := lines_read
    for !reached_end {
        line := peek_line()
        if len(strings.trim_space(line)) == 0 { break }
        if has_any_prefix(line, ..prefixes) { break }
        consume_line()
    }
    return usage_lines[start_idx:lines_read]
}

has_any_prefix :: proc(str: string, prefixes: ..string) -> bool {
    for prefix in prefixes {
        if strings.has_prefix(str, prefix) {
            return true
        }
    }
    return false
}
