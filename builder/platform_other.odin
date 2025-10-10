#+build !windows
package builder

import "core:time"

wait_for_change :: proc(dir: string) {
    panic("Directory watching not implemented for this platform")
    // TODO:
}

remove_file_delayed :: proc(path: string, delay: time.Duration) {
    // TODO:
}
