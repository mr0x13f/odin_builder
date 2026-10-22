#+private file
package tools

import "core:io"
import "core:strings"
import "core:fmt"
import "core:path/filepath"
import "core:os"

OUT_PATH :: "builder/odin_targets.odin"
PACKAGE_NAME :: "builder"

stderr_lines: []string
lines_read: int
reached_end: bool

@private
main :: proc() {

    // Read usage
    command := []string { "odin", "build", ".", "-target:?" }
    _, _, stderr := os.process_exec({ command = command, }, context.allocator) or_else
        panic("Failed to start odin")
    stderr_lines = strings.split_lines(string(stderr))

    // Generate code
    targets_enum_builder := strings.builder_make()

    fmt.sbprintln(&targets_enum_builder, "// Generated with tools/generate_odin_targets.odin")
    fmt.sbprintln(&targets_enum_builder)
    fmt.sbprintln(&targets_enum_builder)
    fmt.sbprintln(&targets_enum_builder, "// Odin build targets, to be used with the `-target` flag")
    fmt.sbprintln(&targets_enum_builder, "Odin_Build_Targets :: enum {")
    fmt.sbprintln(&targets_enum_builder, "    Native,")
    skip_lines_until_prefix("\t")
    for !reached_end {
        line := consume_line()
        defer skip_lines_until_prefix("\t")

        target_name := strings.trim_left_space(line)
        option_name := strings.to_ada_case(target_name, context.temp_allocator)
        fmt.sbprintfln(&targets_enum_builder, "    %s,", option_name)
    }
    fmt.sbprintln(&targets_enum_builder, "}")

    // Write output
    out_path_abs := filepath.join({ filepath.dir(os.args[0]), OUT_PATH  }, context.temp_allocator) or_else panic("Allocation error")
    out_file := os.open(out_path_abs, { .Create, .Write, .Trunc }) or_else
        panic("Failed to open output file")
    defer os.close(out_file)
    out_writer := os.to_writer(out_file)

    fmt.wprintln(out_writer, "package " + PACKAGE_NAME)
    fmt.wprintln(out_writer)
    fmt.wprint(out_writer, strings.to_string(targets_enum_builder))

    fmt.println("Successfully wrote to " + OUT_PATH)

}

peek_line :: proc() -> string {
    return stderr_lines[lines_read]
}

consume_line :: proc() -> (line: string) {
    line = stderr_lines[lines_read]
    lines_read += 1
    reached_end = lines_read >= len(stderr_lines)
    return
}

skip_lines_until_prefix :: proc(prefix: string) {
    for !reached_end && !strings.has_prefix(peek_line(), prefix) {
        consume_line()
    }
}
