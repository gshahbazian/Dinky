import AppKit
import DinkyPrivate

// Follows app activation (Cmd-Tab, Dock click) to the display and Space of the app's window when the
// "switch to a Space with open windows" setting is off. Only activations the user asked for are followed.
// macOS also activates apps on its own, and chasing those throws the user off the Space they are on:
// - Arriving on a Space activates whatever is there (Finder on an empty one). The first activation within
//   `arrivalWindow` of a Space change is ignored unless fresh keyboard or mouse input arrived.
// - When the active app quits, hides or loses its last window on the current Space, macOS activates another
//   app. An activation within `goneWindow` of the previous app going away is that one.

private let ms: UInt64 = 1_000_000
private let arrivalWindow = 300 * ms
private let goneWindow = 300 * ms

// The last Space seen on each display, updated whenever the display model changes and checked again on every
// activation, since the model may not have caught up with a swipe posted by another process yet.
private var lastSeenSpaceIDs: [String: UInt64] = [:]
private var lastSpaceChangeAt: UInt64 = 0
/// No activation has arrived since the last Space change.
private var arrivalPending = false
private var arrivalInput: [UInt64] = []
/// The app that last quit, hid or lost a window, and when.
private var lastGone: (pid: pid_t, at: UInt64) = (0, 0)
private var activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
/// The last few follows, to notice a loop: dinky and macOS chasing each other's activations between two
/// Spaces. `loopFollows` follows within `loopWindow` pause following for `loopPause`, logged with the trail.
private var recentFollows: [(at: UInt64, text: String)] = []
private var followInput: [UInt64] = []
private var requestedApp: pid_t = 0
private var pausedUntil: UInt64 = 0
private let loopFollows = 4
private let loopWindow = 3_000 * ms
private let loopPause = 5_000 * ms

// Records the current Space of every display as the model has it; a difference from the last one recorded
// is a Space change.
private func noteCurrentSpace() {
    let model = AppState.shared.displays
    let seen = Dictionary(model.displays.map { ($0.uuid, $0.currentSpaceID) }, uniquingKeysWith: { a, _ in a })
    guard seen != lastSeenSpaceIDs else { return }
    lastSeenSpaceIDs = seen
    spaceChanged()
}

// Tells the activation follower that this Space change, or this activation on the current Space, is
// dinky's own, so the activation it causes is not followed.
func noteOwnSwitch(to target: UInt64, on uuid: String) {
    lastSeenSpaceIDs[uuid] = target
    spaceChanged()
}

private func spaceChanged() {
    lastSpaceChangeAt = uptime()
    arrivalPending = true
    arrivalInput = inputCounts()
}

func installActivationFollower() {
    noteCurrentSpace()
    AppState.shared.displays.observe { _ in noteCurrentSpace() }
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
        center.addObserver(forName: name, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            lastGone = (app.processIdentifier, uptime())
        }
    }
    center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let previous = activePID
        activePID = app.processIdentifier
        let name = app.localizedName ?? "?"
        guard AppState.shared.enabled, AppState.shared.config.followAppActivation else { return }
        if inputCounts() != followInput {
            pausedUntil = 0
            recentFollows = []
        }
        guard uptime() >= pausedUntil else { return log("activate \(name): not followed, following is paused") }
        guard !isArrivalActivation() else { return log("activate \(name): not followed, macOS activated it on arrival") }
        activated(app.processIdentifier, name: name, previous: previous)
    }
}

// Remembers the owner of each window that closes, as an app losing a window. Call once, with the coordinator's
// window model.
func noteGoneWindows(in model: WindowModel) {
    model.observe { event in
        guard [.windowClose, .windowDestroy].contains(event.kind) else { return }
        let pid = event.window?.pid ?? event.pid
        if pid != 0 { lastGone = (pid, uptime()) }
    }
}

// Consumes the arrival: only the first activation after a Space change can be the one it causes. Reads the
// displays afresh first, as the activation can arrive before anything told the model about the Space change.
private func isArrivalActivation() -> Bool {
    AppState.shared.displays.reconcile()
    noteCurrentSpace()
    defer { arrivalPending = false }
    return arrivalPending && inputCounts() == arrivalInput && uptime() - lastSpaceChangeAt < arrivalWindow
}

// Stays if the app has a window on the focused display's current Space; otherwise follows immediately.
private func activated(_ pid: pid_t, name: String, previous: pid_t) {
    requestedApp = pid
    guard let here = AppState.shared.displays.focusedDisplay()?.currentSpaceID else {
        return log("activate \(name): not followed, no focused display")
    }
    if windowSpaces(of: pid).contains(here) {
        // A new activation can reverse a switch still in flight. Replace its destination too.
        let model = AppState.shared.displays
        if let display = model.display(containingSpace: here), targetSpaceID(on: display) != here,
           let id = normalWindows(of: pid, [.optionAll]).first(where: { dinky_window_space_id($0) == here }),
           let identity = AppState.shared.coordinator?.model.windows[id]?.identity {
            switchSpace(toSpaceID: here, on: display) {
                guard requestedApp == pid, AppState.shared.coordinator?.model.windows[id]?.identity == identity else { return }
                AppState.shared.coordinator?.focus(id)
                AppState.shared.coordinator?.syncFocus()
            }
        }
        return log("activate \(name): stayed, it has a window here")
    }
    guard lastGone.pid != previous || lastGone.at + goneWindow <= uptime() || hasWindowOnScreen(previous) else {
        return log("activate \(name): not followed, macOS replaced the app that went away")
    }
    follow(pid, name: name)
}

private func log(_ message: String) {
    print("\(stamp()) \(message)")
    fflush(stdout)
}

// New input separates deliberate app switches from repeated automatic activations.
private func inputCounts() -> [UInt64] {
    [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].map {
        UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: $0))
    }
}

// Only follows without intervening input contribute to the loop guard.
private func noteFollow(_ text: String) {
    let now = uptime()
    let input = inputCounts()
    if input != followInput { recentFollows = [] }
    followInput = input
    recentFollows = recentFollows.filter { now - $0.at < loopWindow } + [(now, text)]
    guard recentFollows.count >= loopFollows else { return }
    pausedUntil = now + loopPause
    let trail = recentFollows.map { String(format: "%.0f ms ago: %@", Double(now - $0.at) / 1_000_000, $0.text) }
    fputs("\(stamp()) activate: \(recentFollows.count) follows in \(loopWindow / (1_000 * ms)) s look like a loop; "
        + "not following for \(loopPause / (1_000 * ms)) s\n  " + trail.joined(separator: "\n  ") + "\n", stderr)
    recentFollows = []
}

// The Spaces of the app's normal windows, front to back: the first one is its frontmost window's.
private func windowSpaces(of pid: pid_t) -> [UInt64] {
    normalWindows(of: pid, [.optionAll]).map { dinky_window_space_id($0) }
}

// Whether the app shows a normal window on a current Space; a hidden app does not.
private func hasWindowOnScreen(_ pid: pid_t) -> Bool {
    !normalWindows(of: pid, [.optionOnScreenOnly]).isEmpty
}

// Only the windows the window model tracks as normal count, so an app's hidden helper windows, which can sit
// on any Space, don't. The window server's list supplies the front-to-back order.
private func normalWindows(of pid: pid_t, _ options: CGWindowListOption) -> [UInt32] {
    let known = AppState.shared.coordinator?.model.windows ?? [:]
    let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return info.compactMap { w in
        guard w[kCGWindowOwnerPID as String] as? pid_t == pid, w[kCGWindowLayer as String] as? Int == 0,
              let id = w[kCGWindowNumber as String] as? UInt32, known[id]?.isNormal == true else { return nil }
        return id
    }
}

// Prefer confirmed focus history, then the app's AX main window, then stacking order.
private func follow(_ pid: pid_t, name: String) {
    let state = AppState.shared
    let model = state.displays
    guard uptime() >= pausedUntil else { return log("activate \(name): not followed, following is paused") }
    let windows = normalWindows(of: pid, [.optionAll])
    var candidates = windows
    let main = mainWindowID(of: pid)
    if windows.contains(main) {
        candidates.removeAll { $0 == main }
        candidates.insert(main, at: 0)
    }
    if let identity = state.coordinator?.appFocusHistory.lastFocused(for: pid),
       state.coordinator?.model.windows[identity.id]?.identity == identity, windows.contains(identity.id) {
        candidates.removeAll { $0 == identity.id }
        candidates.insert(identity.id, at: 0)
    }
    guard let (id, space, display) = candidates.lazy.compactMap({ id -> (UInt32, UInt64, Display)? in
        let space = dinky_window_space_id(id)
        guard let display = model.display(containingSpace: space) else { return nil }
        return (id, space, display)
    }).first else {
        return log("activate \(name): not followed, no window has an available Space")
    }
    let identity = state.coordinator?.model.windows[id]?.identity
    let arrive = {
        guard requestedApp == pid, let identity, state.coordinator?.model.windows[id]?.identity == identity else { return }
        bringForward(id, of: pid, name: name)
        state.coordinator?.syncFocus()
    }
    guard space != display.currentSpaceID else {
        arrive()
        return log("activate \(name): not followed, already on Space \(space)")
    }
    let from = state.numbers.label(of: display.currentSpaceID)
    guard switchSpace(toSpaceID: space, on: display, landed: arrive) else { return }
    let text = "activate \(name): followed workspace \(from) -> \(state.numbers.label(of: space))"
        + " on \(display.name.isEmpty ? "display \(display.id)" : display.name), window \(id)"
    log(text)
    noteFollow(text)
}

// macOS activates an app on every Space a swipe passes and on the one it lands on, and the arrival rule takes the
// first of those for its own. One of them can leave another app in front of the one the user chose: one whose window
// is on top there, or one picked on a Space passed on the way that also has a window here. Focus the window once
// the display is on its Space.
private func bringForward(_ window: UInt32, of pid: pid_t, name: String) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid || frontWindowID() != window else { return }
    log("activate \(name): brought its window forward after the switch")
    if let coordinator = AppState.shared.coordinator, coordinator.model.windows[window] != nil {
        coordinator.focus(window)
    } else {
        focusWindow(pid: pid, id: window)
    }
}
