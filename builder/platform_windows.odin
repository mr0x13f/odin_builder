#+build windows
package builder

import "core:time"
import "core:fmt"
import "core:path/filepath"
import "core:sys/windows"

CHANGE_NOTIFICATION_FILTER :: windows.FILE_NOTIFY_CHANGE_FILE_NAME |
    windows.FILE_NOTIFY_CHANGE_DIR_NAME |
    windows.FILE_NOTIFY_CHANGE_SIZE |
    windows.FILE_NOTIFY_CHANGE_LAST_WRITE

wait_for_change :: proc(dir: string) {
    dir_abs_w := windows.utf8_to_wstring(to_abs_path(dir), context.temp_allocator)

    notification := windows.FindFirstChangeNotificationW(transmute([^]u16)dir_abs_w, true, CHANGE_NOTIFICATION_FILTER)
    windows.WaitForSingleObject(notification, windows.INFINITE)
    windows.FindCloseChangeNotification(notification)

    // HACK: Wait for a little bit to ensure the file write is complete
    time.sleep(100 * time.Millisecond)
}

remove_file_delayed :: proc(path: string) {
    cmd := fmt.tprintf("cmd /C del \"%s\"", to_abs_path(path))
    cmd_w := windows.utf8_to_wstring(cmd, context.temp_allocator)

    si: windows.STARTUPINFOW
    pi: windows.PROCESS_INFORMATION
    creation_flags: u32 = windows.CREATE_NO_WINDOW | windows.DETACHED_PROCESS

    ok := windows.CreateProcessW( nil, cmd_w, nil, nil, false, creation_flags, nil, nil, &si, &pi )

    windows.CloseHandle(pi.hProcess)
    windows.CloseHandle(pi.hThread)
}

@(private="file")
to_abs_path :: proc(path: string) -> string {
    abs_path, abs_ok := filepath.abs(path, context.temp_allocator)
    if !abs_ok { error("Failed to make path absolute: %s", path) }
    return abs_path
}
