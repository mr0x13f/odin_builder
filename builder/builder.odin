package builder

import "core:path/slashpath"
import "core:strings"
import "base:runtime"
import "core:time"
import "core:terminal/ansi"
import "core:slice"
import "core:reflect"
import "core:fmt"
import "core:os"
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

WINDOWS :: "windows"
LINUX   :: "linux"
MACOS   :: "macos"

NATIVE_WINDOWS :: ODIN_OS == .Windows
NATIVE_LINUX   :: ODIN_OS == .Linux
NATIVE_MACOS   :: ODIN_OS == .Darwin

WINDOWS_EXTENSIONS :: Extensions { ".exe",  ".dll",   ".lib",    ".obj"    }
LINUX_EXTENSIONS   :: Extensions { "",      ".so",    ".a",      ".o"      }
MACOS_EXTENSIONS   :: Extensions { "",      ".dylib", ".a",      ".o"      }
WASM_EXTENSIONS    :: Extensions { ".wasm", ".wasm",  ".wasm.a", ".wasm.o" }
MINGW_EXTENSIONS   :: Extensions { ".exe",  ".dll",   ".a",      ".o"      }

EXTENSION_ASSEMBLY :: ".s"
EXTENSION_LLVM_IR :: ".ll"

when NATIVE_WINDOWS {
    NATIVE_PLATFORM :: WINDOWS
    NATIVE_EXTENSIONS :: WINDOWS_EXTENSIONS
}
when NATIVE_LINUX {
    NATIVE_PLATFORM :: LINUX
    NATIVE_EXTENSIONS :: LINUX_EXTENSIONS
}
when NATIVE_MACOS {
    NATIVE_PLATFORM :: MACOS
    NATIVE_EXTENSIONS :: MACOS_EXTENSIONS
}

Extensions :: struct {
    executable: string,
    dynamic_library: string,
    static_library: string,
    object: string,
}

// Working directory, same as the directory of the build script
cwd: string
// Command line arguments without prefix (-, --, /)
cli_args: []string

// Uses the command line arguments to set the value of the fields in the supplied struct by their field names.
// Also sets the working directory to the location of the calling file.
// Also sets other global fields in the `builder` package.
read_args :: proc(args: ^$T, check_args := true, caller_loc := #caller_location) {
    // TODO: use core:flags.parse_or_exit
    // cwd
    cwd = filepath.dir(caller_loc.file_path)
    os.set_working_directory(cwd)
    // args
    // TODO: strip arg prefixes like '-', '--', '/',
    // TODO: consider using core:flags
    cli_args = os.args[1:]
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
            exit(1)
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

// Join all `elems` with the system's path separator and normalize the result.
// Works the same as filepath.join except with #optional_allocator_error.
//
// *Allocates Using Provided Allocator*
//
// For example, `join({"/home", "foo", "bar.txt"})` will result in `"/home/foo/bar.txt"`.
join :: proc(elems: ..string, allocator := context.allocator) -> (joined: string, err: runtime.Allocator_Error) #optional_allocator_error {
	return filepath.join(elems, allocator)
}

// Exit immediately and clean up
exit :: proc(code: int = 0) -> ! {
    exe_path := os.args[0]
    // Using os.exit() causes `odin run` to not be able to remove the temporary exe it creates
    // so we manually clean it up
    remove_file_delayed(exe_path)
    os.exit(code)
}

// Show a formatted error message and exit
error :: proc(format: string, args: ..any) -> ! {
    fmt.print(FG_RED)
    fmt.print("[ERROR] ")
    fmt.printf(format, ..args)
    fmt.print(RESET)
    exit(1)
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
    path := filepath.join(parts, context.temp_allocator) or_else panic("Allocator error")
    os.make_directory_all(path)
}

// Create a child process and wait for it to complete. Its stdout and stderr are forwarded to the console unless silent is set to true.
call :: proc(command: ..[]string, environment: []string = nil, silent := false, interactive := false) -> (success: bool) {

    command_parts := slice.concatenate(command, context.temp_allocator)
    executable := command[0][0]
    stderr := silent ? nil : os.stderr
    stdout := silent ? nil : os.stdout
    stdin := interactive ? os.stdin : nil

    process, err := os.process_start({
        command     = command_parts,
        working_dir = cwd,
        env         = environment,
        stderr      = stderr,
        stdout      = stdout,
        stdin       = stdin,
    })
    if err != nil && !silent {
        fmt.printfln(FG_RED + "Error running %s: %s", executable, os.error_string(err))
        return false
    }

    state, wait_err := os.process_wait(process)
    if wait_err != nil && !silent {
        fmt.printfln(FG_RED + "Error waiting for %s to complete: %s", executable, os.error_string(wait_err))
        return false
    }

    success = state.exit_code == 0
    if !success && !silent {
        fmt.printfln(FG_RED + "Process %s exited with code: %i" + RESET, executable, state.exit_code)
        return false
    }

    return true
}

get_target_name :: proc (target: Odin_Build_Targets) -> string {
    if (target == .Native) {
        return NATIVE_PLATFORM
    }
    return reflect.enum_name_from_value(target) or_else panic("Bad target value")
}

// Verifies that only one of the given booleans is true, otherwise exits the program
expect_exactly_one_of :: proc (flags: ..bool, call_expr := #caller_expression) {
    if count(..flags) != 1 {
        flags_start := strings.index(call_expr, "(") + 1
        flags_end := strings.index(call_expr, ")")
        flags_expr := call_expr[flags_start:flags_end]
        error("Expected exactly ONE of: %s", flags_expr)
    }
}

// Copies or overwrites a file from src_path to dst_path. Creates directories if necessary.
// Exits if there is a failure.
copy :: proc (dst_path: string, src_path: string) {
    mkdir(filepath.dir(dst_path))
    err := os.copy_file(dst_path, src_path) 
    if err != nil {
        error("Failed to copy file: %s", err)
    }
}

// Moves/renames file from src_path to dst_path. Creates directories if necessary.
// Exits if there is a failure.
move :: proc (src_path: string, dst_path: string) {
    mkdir(filepath.dir(dst_path))
    err := os.rename(src_path, dst_path) 
    if err != nil {
        error("Failed to move file: %s", err)
    }
}

// Deletes contents of directory and ensures the directory exists
clear_dir :: proc(path: string) {
    err := os.remove_all(path)
    if err != nil && err != .Not_Exist {
        error("Failed to clean %s: %s", path, err)
    }
    mkdir(path)
}
