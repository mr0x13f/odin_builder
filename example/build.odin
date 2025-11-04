#+vet !using-stmt
package build

import "core:os/os2"
import "core:path/filepath"
import "core:strings"
import "core:fmt"
import "../builder"

/*
    ===== Usage =====
        odin run . -- [..args]

    ===== Examples =====
    Debug build:
        odin run . -- debug
    Release build:
        odin run . -- release
    Watch-for-changes debug build without vetting:
        odin run . -- debug watch novet
*/

args: struct {
    debug:   bool "Debug build mode",
    release: bool "Release build mode",
    watch:   bool "Watch for changes",
    vet:     bool "Extra vetting",
    novet:   bool "No vetting",
    asan:    bool "Use address sanitizer",
    help:    bool "Show usage",
}

main :: proc() {
    using args, builder
    read_args(&args)

    if help || len(cli_args) == 0 {
        print_usage(&args); exit(1) }

    if count(debug, release) != 1 {
        error("Wrong number of build modes, expected 'debug' OR 'release'") }

    // Info
    app_name      := "hellope"
    odin_main_pkg := "hellope"
    odin_main_dir := "src"
    build_dir     := "build"

    // Prepare Build
    build_mode := debug ? "debug" : release ? "release" : ""
    build_name := fmt.aprintf("%s %s", strings.to_pascal_case(PLATFORM), strings.to_pascal_case(build_mode))
    fmt.printfln("[%s build]", build_name)
    out_dir := filepath.join({ build_dir, build_mode })
    
    // Build flags
    odin_out: string
    build_options: Build_Options

    if debug {
        odin_out = filepath.join({ out_dir, fmt.aprintf("%s_%s_%s", app_name, PLATFORM, build_mode) })
        build_options.debug = true
        build_options.optimization = .Minimal
        if WINDOWS {
            build_options.subsystem = .Console
            build_options.linker = .Radlink
        } 
    }
    if release {
        odin_out = filepath.join({ out_dir, app_name })
        build_options.disable_assert = true
        build_options.optimization = .Speed
        if WINDOWS { build_options.subsystem = .Windows }
    }

    if asan { build_options.sanitize = .Address }
    if vet  { build_options.vet_unused_procedures = true }
    if !novet {
        build_options.vet_cast = true
        build_options.vet_semicolon = true
        build_options.vet_shadowing = true
        build_options.vet_style = true
        build_options.vet_unused_imports = true
        build_options.vet_unused_variables = true
        build_options.vet_using_param = true
        build_options.vet_using_stmt = true
    }

    build_options.vet_packages = { odin_main_pkg }

    // Compile
    for watch_dir(watch, odin_main_dir) {
        
        fmt.printfln("Building %s...", app_name)
        build_success := build(odin_main_dir, odin_out, .Executable, build_options)

        if build_success {
            fmt.printfln(FG_GREEN + "%s build created in " + FG_CYAN + "%s" + os2.Path_Separator_String + RESET, build_name, out_dir)
        } else {
            fmt.printfln(FG_RED + "%s build failed" + RESET, build_name)
            if !watch { exit(-1) }
        }
    }
}
