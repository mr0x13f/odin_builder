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
    app_name := "hellope"
    odin_main_pkg := "hellope"
    odin_main_dir := "src"
    build_dir := "build"

    // Prepare Build
    build_mode := debug ? "debug" : release ? "release" : ""
    build_name := fmt.aprintf("%s %s", strings.to_pascal_case(platform), strings.to_pascal_case(build_mode))
    fmt.printfln("[%s build]", build_name)
    exe_ext := windows ? ".exe" : ""
    out_dir := filepath.join({ build_dir, build_mode })
    
    // Build flags
    odin_flags := make([dynamic]string)
    odin_out: string

    if debug {
        odin_out = filepath.join({ out_dir, fmt.aprintf("%s_%s_%s%s", app_name, platform, build_mode, exe_ext) })
        append(&odin_flags, "-debug", "-o:minimal")
        if windows { append(&odin_flags, "-subsystem:console", "-linker:radlink") } 
    }
    if release {
        odin_out = filepath.join({ out_dir, fmt.aprintf("%s%s", app_name, exe_ext) })
        append(&odin_flags, "-disable-assert", "-o:speed")
        if windows { append(&odin_flags, "-subsystem:windows") }
    }

    if !novet { append(&odin_flags, "-vet-cast", "-vet-semicolon", "-vet-shadowing", "-vet-style", "-vet-unused-imports", "-vet-unused-variables", "-vet-using-param", "-vet-using-stmt") }
    if vet    { append(&odin_flags, "-vet-unused-procedures") }
    if asan   { append(&odin_flags, "-sanitize:address") }

    append(&odin_flags, fmt.aprintf("-vet-packages:%s", odin_main_pkg))
    append(&odin_flags, fmt.aprintf("-out:%s", odin_out))

    // Compile
    for watch_dir(watch, odin_main_dir) {
        
        fmt.printfln("Compiling %s...", app_name)
        mkdir(out_dir)
        build_success := call({ "odin", "build", odin_main_dir }, odin_flags[:] )

        if build_success {
            fmt.printfln(FG_GREEN + "%s build created in " + FG_CYAN + "%s" + os2.Path_Separator_String + RESET, build_name, out_dir)
        } else {
            fmt.printfln(FG_RED + "%s build failed" + RESET, build_name)
            if !watch { exit(-1) }
        }
    }
}
