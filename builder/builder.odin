package builder

import "core:time"
import "core:terminal/ansi"
import "core:slice"
import "core:reflect"
import "core:fmt"
import "core:strings"
import "core:os/os2"
import "core:path/filepath"

RESET      :: ansi.CSI + ansi.RESET      + ansi.SGR
FG_BLACK   :: ansi.CSI + ansi.FG_BLACK   + ansi.SGR
FG_RED     :: ansi.CSI + ansi.FG_RED     + ansi.SGR
FG_GREEN   :: ansi.CSI + ansi.FG_GREEN   + ansi.SGR
FG_YELLOW  :: ansi.CSI + ansi.FG_YELLOW  + ansi.SGR
FG_BLUE    :: ansi.CSI + ansi.FG_BLUE    + ansi.SGR
FG_MAGENTA :: ansi.CSI + ansi.FG_MAGENTA + ansi.SGR
FG_CYAN    :: ansi.CSI + ansi.FG_CYAN    + ansi.SGR
FG_WHITE   :: ansi.CSI + ansi.FG_WHITE   + ansi.SGR

// Whether the current platform is Windows
windows: bool
// Whether the current platform is Linux
linux:   bool
// Whether the current platform is macOS (Darwin)
macos:   bool

// Working directory, same as the directory of the build script
cwd: string
// Command line arguments without prefix (-, --, /)
cli_args: []string
// Name of the current platform: `"windows"` or `"linux"` or `"macos"`
platform: string
// Extension for executables on this platform
exe_ext: string
// Extension for shared/dynamic libraries on this platform
dll_ext: string

// Uses the command line arguments to set the value of the fields in the supplied struct by their field names.
// Also sets the working directory to the location of the calling file.
// Also sets other global fields in the `builder` package.
read_args :: proc(args: ^$T, check_args := true, caller_loc := #caller_location) {
    // TODO: use core:flags.parse_or_exit
    // cwd
    cwd = filepath.dir(caller_loc.file_path)
    os2.set_working_directory(cwd)
    // platform
    windows = ODIN_OS == .Windows
    linux   = ODIN_OS == .Linux
    macos   = ODIN_OS == .Darwin
    platform = "macos" if macos else strings.to_lower(reflect.enum_string(ODIN_OS))
    exe_ext = windows ? ".exe" : ""
    dll_ext = windows ? ".dll" : linux ? ".so" : macos ? ".dylib" : ""
    // args
    // TODO: strip arg prefixes like '-', '--', '/',
    // TODO: consider using core:flags
    cli_args = os2.args[1:]
    if check_args { validate_args(args, cli_args) }
    set_fields_true(args, cli_args)
}

// Watches the supplied directory (and its sub directories) if the `watch` parameter is `true`.
// Waits until a change is detected, then returns `true`.
// Also frees the `context.temp_allocator`.
// If `watch` is false, will return `true` once and then `false`.
// To be used in a `for` loop.
// If the build edits files inside the watch directory, you should set the
// `delay` parameter to avoid the changes triggering another build.
watch_dir :: proc(watch: bool, dir: string, delay: time.Duration = 0) -> bool {
    @static first := true
    if first {
        first = false;
        return true
    }
    if !watch { return false }

    // Optionally wait to make sure any files created by the previous compile
    // don't trigger the directory watching
    time.sleep(delay)

    fmt.println()
    fmt.println("Waiting for file changes...")
    wait_for_change(dir)
    fmt.println("Files changed")
    
    free_all(context.temp_allocator)
    return true
}

// Validates the cli args against the field names of the given struct.
// If any cli args do not match a field name, it will print a usage message and exit.
validate_args :: proc(args_struct: ^$T, cli_args: []string) {
    valid_arg_names := reflect.struct_field_names(T)
    for arg in cli_args {
        if !slice.contains(valid_arg_names, arg) {
            fmt.printfln(FG_RED + "Invalid argument: %s" + RESET, arg)
            print_usage(args_struct)
            exit(-1)
        }
    }
}

// Sets fields of the given struct to `true` if their name appears in `field_names`
set_fields_true :: proc(strct: ^$T, field_names: []string) {
    for field in reflect.struct_fields_zipped(T) {
        slice.contains(field_names, field.name) or_continue
        if field.type.id != typeid_of(bool) {
            fmt.panicf("Invalid arg field type \"%s\", expected bool", field.type) }
        field_ptr := cast(^bool)(uintptr(strct) + field.offset)
        field_ptr ^= true
    }
}

// Count the number of true bools in the passed arguments
count :: proc(conditions: ..bool) -> (count: int) {
    for cond in conditions { count += int(cond) }
    return
}

// Exit immediately and clean up
exit :: proc(code: i32 = 0) -> ! {
    exe_path := os2.args[0]
    // Using os2.exit() causes `odin run` to not be able to remove the temporary exe it creates
    // so we manually clean it up
    remove_file_delayed(exe_path)
    os2.exit(-1)
}

// Show a formatted error message and exit
error :: proc(format: string, args: ..any) -> ! {
    fmt.print(FG_RED)
    fmt.print("[ERROR] ")
    fmt.printf(format, ..args)
    fmt.print(RESET)
    exit(-1)
}

// Prints a usage message to the console based on the provided args struct.
// The names of the fields in the struct will be the names of the arguments
// and the tag will be the description.
print_usage :: proc(args: ^$T) {
    fmt.println("Usage:")
    fmt.println("    odin run . -- [..args]")
    fmt.println("Arguments:")
    for field in reflect.struct_fields_zipped(T) {
        fmt.printfln("    %-8s  %s", field.name, field.tag)
    }
}

// Ensures a directory (and its parents) exist
mkdir :: proc(parts: ..string) {
    os2.make_directory_all(filepath.join(parts, context.temp_allocator))
}

// Create a child process and wait for it to complete. Its stdout and stderr are forwarded to the console.
call :: proc(command: ..[]string, environment: []string = nil) -> (success: bool) {
    env := environment
    if env != nil {
        err: os2.Error
        env, err = os2.environ(context.temp_allocator)
        if err != nil { error("Error while getting environment variables: %s", os2.error_string(err)) }
    }

    command_parts := slice.concatenate(command, context.temp_allocator)
    executable := command[0][0]

    process, err := os2.process_start({
        command     = command_parts,
        working_dir = cwd,
        env         = env,
        stderr      = os2.stderr,
        stdout      = os2.stdout,
        stdin       = nil,
    })
    if err != nil { error("Error running %s: %s", executable, os2.error_string(err)) }

    state, wait_err := os2.process_wait(process)
    if wait_err != nil { error("Error waiting for %s to complete: %s", executable, os2.error_string(wait_err)) }

    success = state.exit_code == 0
    if !success { fmt.printfln(FG_RED + "Process %s exited with code: %i" + RESET, executable, state.exit_code) }
    return
}
