#import "focus.h"
#import "skylight.h"

// yabai src/window_manager.c, window_manager_focus_window_with_raise and window_manager_make_key_window, at
// https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/window_manager.c#L1269-L1335
// When focus stops landing on the window after a macOS update, compare those two functions with this file.

// yabai src/window_manager.h.
static const uint32_t kCPSUserGenerated = 0x200;

// Two synthesized event records that make the window key, as yabai window_manager_make_key_window posts them.
static void make_key_window(ProcessSerialNumber *psn, uint32_t windowID)
{
    uint8_t bytes[0xf8] = {0};
    bytes[0x04] = 0xf8;
    bytes[0x3a] = 0x10;
    memcpy(bytes + 0x3c, &windowID, sizeof(uint32_t));
    memset(bytes + 0x20, 0xff, 0x10);

    bytes[0x08] = 0x01;
    SLPSPostEventRecordTo(psn, bytes);

    bytes[0x08] = 0x02;
    SLPSPostEventRecordTo(psn, bytes);
}

bool dinky_focus_window(pid_t pid, uint32_t windowID)
{
    ProcessSerialNumber psn = {0};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (GetProcessForPID(pid, &psn) != noErr) return false;
#pragma clang diagnostic pop
    if (_SLPSSetFrontProcessWithOptions(&psn, windowID, kCPSUserGenerated) != kCGErrorSuccess) return false;
    make_key_window(&psn, windowID);
    return true;
}
