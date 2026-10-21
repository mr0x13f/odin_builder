#+build !windows
package builder

wait_for_change :: proc(dir: string) {
    panic("Directory watching not implemented for this platform")
    // TODO:
}

remove_file_delayed :: proc(path: string) {
    // TODO:
}
