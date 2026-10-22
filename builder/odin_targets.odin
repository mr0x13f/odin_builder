package builder

// Generated with tools/generate_odin_targets.odin


// Odin build targets, to be used with the `-target` flag
Odin_Build_Targets :: enum {
    Native,
    Darwin_Amd64,
    Darwin_Arm64,
    Linux_I386,
    Linux_Amd64,
    Linux_Arm64,
    Linux_Arm32,
    Linux_Riscv64,
    Windows_I386,
    Windows_Amd64,
    Freebsd_I386,
    Freebsd_Amd64,
    Freebsd_Arm64,
    Netbsd_Amd64,
    Netbsd_Arm64,
    Openbsd_Amd64,
    Freestanding_Wasm32,
    Wasi_Wasm32,
    Js_Wasm32,
    Orca_Wasm32,
    Freestanding_Wasm64p32,
    Js_Wasm64p32,
    Wasi_Wasm64p32,
    Freestanding_Amd64_Sysv,
    Freestanding_Amd64_Win64,
    Freestanding_Amd64_Mingw,
    Freestanding_Arm64,
    Freestanding_Arm32,
    Freestanding_Riscv64,
}
