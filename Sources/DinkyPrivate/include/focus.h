#pragma once
#import <Foundation/Foundation.h>

// Brings the app forward with windowID as its key window, in the window server rather than through app
// activation. Activating the app races the window made key: it can keep the key window it had before, one on
// another display. Callers pass a window on a current Space; given one on another Space, macOS may switch to it.
// Returns whether the app was found and brought forward.
bool dinky_focus_window(pid_t pid, uint32_t windowID);
