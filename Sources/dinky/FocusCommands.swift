import AppKit
import DinkyCommands
import DinkyLayout
import DinkyPrivate

// `focus` with AeroSpace's boundaries, and `focus-monitor`. Display geometry comes from the display model;
// a display is entered at the window snapped to the edge focus comes in by.
extension Dispatcher {
    /// Tiled and floating windows share the same spatial navigation and wrap behavior.
    static func focus(_ direction: Direction, boundaries: FocusBoundaries, action: BoundariesAction) -> Reply {
        guard let coordinator = AppState.shared.coordinator,
              let front = coordinator.model.windows[coordinator.focusedWindow] else { return focusOnScreen(direction) }
        let windows = coordinator.model.windows.values.filter {
            $0.spaceID == front.spaceID && $0.isNormal && !$0.isMinimized
        }
        var frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        if let display = AppState.shared.displays.display(containingSpace: front.spaceID),
           let workspace = coordinator.workspace(on: display) {
            frames = workspace.directionalFrames(frames, direction: direction)
        }
        let from = frames[front.id] ?? front.frame
        let candidates = frames.filter { $0.key != front.id }.map { ($0.key, $0.value) }
        if let id = directionalWindow(from: from, candidates: candidates, direction: direction) {
            return focus(window: id)
        }
        let model = AppState.shared.displays
        if boundaries == .allMonitorsOuterFrame, let from = model.display(ofWindow: coordinator.focusedWindow) {
            let line = displays(inLineWith: from, direction.orientation, model.displays)
            let index = line.firstIndex(of: from)! + (direction.isForward ? 1 : -1)
            if line.indices.contains(index) { return enter(line[index], from: direction) }
            if action == .wrapAroundAllMonitors { return enter(direction.isForward ? line[0] : line[line.count - 1], from: direction) }
        }
        switch action {
        case .stop, .wrapAroundAllMonitors:
            return .ok("no window \(direction)")
        case .fail:
            return .error("no window \(direction)")
        case .wrapAroundTheWorkspace:
            guard let id = wrappedDirectionalWindow(from: from, candidates: candidates, direction: direction) else {
                return .ok("no window to wrap around to")
            }
            return focus(window: id)
        }
    }

    static func focusBackAndForth() -> Reply {
        let state = AppState.shared
        guard let coordinator = state.coordinator else { return .error("tiling is not running") }
        coordinator.syncFocus()
        guard let previous = coordinator.focusHistory.previous,
              let window = coordinator.model.windows[previous.id], window.identity == previous else {
            return .error("no previous focused window")
        }
        let liveSpace = dinky_window_space_id(window.id)
        let space = liveSpace == 0 ? coordinator.focusedSpaces[window.id] : liveSpace
        state.displays.reconcile()
        guard let space, let display = state.displays.display(containingSpace: space) else {
            return .error("previous window has no available Space")
        }
        let history = coordinator.focusHistory
        let arrive = {
            guard coordinator.model.windows[previous.id]?.identity == previous else { return }
            coordinator.focusHistory = history
            coordinator.focus(previous.id)
            MouseFollowFocus.shared.focusedByCommand(previous.id)
            coordinator.syncFocus()
        }
        MouseFollowFocus.shared.focusedByCommand(previous.id)
        if display.currentSpaceID == space && targetSpaceID(on: display) == space {
            arrive()
        } else if !switchSpace(toSpaceID: space, on: display, landed: arrive) {
            return .error("switch to previous window's Space failed")
        }
        return .ok("focused previous window \(previous.id)")
    }

    /// Focuses a display's most recently focused window, or the display itself when it has none.
    static func focusMonitor(_ target: MonitorTarget) -> Reply {
        let model = AppState.shared.displays
        model.reconcile()
        guard let from = model.focusedDisplay() else { return .error("no display") }
        let line = target.direction.map { displays(inLineWith: from, $0.orientation, model.displays) }
            ?? model.displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        let forward = target.direction?.isForward ?? (target == .next)
        let index = line.firstIndex(of: from)! + (forward ? 1 : -1)
        guard line.indices.contains(index) else {
            return .error(target.direction == nil ? "no \(target.rawValue) display" : "no display \(target.rawValue) of the focused one")
        }
        return focus(line[index], window: AppState.shared.coordinator?.workspace(on: line[index])?.focused)
    }

    /// Focuses the display numbered `n` (1-based, `list-monitors` order), as `focusMonitor` does. Focusing the
    /// display that already has focus is fine, so a bar can run `focus-monitor N` before `workspace M`.
    static func focusMonitor(number n: Int) -> Reply {
        let model = AppState.shared.displays
        model.reconcile()
        guard model.displays.indices.contains(n - 1) else { return .error("no display \(n), there are \(model.displays.count)") }
        let display = model.displays[n - 1]
        return focus(display, window: AppState.shared.coordinator?.workspace(on: display)?.focused)
    }

    /// Enters a display from `direction`: the window at the edge facing where focus came from.
    private static func enter(_ display: Display, from direction: Direction) -> Reply {
        focus(display, window: AppState.shared.coordinator?.workspace(on: display)?.edgeWindow(direction.opposite))
    }

    /// Focuses `window`, or, with none, makes `display` the focused one until focus next changes.
    static func focus(_ display: Display, window: WindowID?) -> Reply {
        if let window { return focus(window: window) }
        let model = AppState.shared.displays
        model.focusOverride = display.uuid
        return .ok("focused display \((model.displays.firstIndex(of: display) ?? 0) + 1)")
    }

    private static func focus(window id: WindowID) -> Reply {
        guard let coordinator = AppState.shared.coordinator, let window = coordinator.model.windows[id] else {
            return .error("window \(id) is gone")
        }
        coordinator.focus(id)
        MouseFollowFocus.shared.focusedByCommand(id)
        return .ok("focused window \(id) \(window.appName ?? "")")
    }

    /// Displays in the same row (for a horizontal axis) or column as `from`, `from` included, ordered along it.
    private static func displays(inLineWith from: Display, _ axis: Orientation, _ all: [Display]) -> [Display] {
        let horizontal = axis == .horizontal
        return all.filter { d in
            d == from || (horizontal ? min(d.frame.maxY, from.frame.maxY) > max(d.frame.minY, from.frame.minY)
                                     : min(d.frame.maxX, from.frame.maxX) > max(d.frame.minX, from.frame.minX))
        }.sorted { horizontal ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }
    }

    /// Navigate visible windows, entering from the opposite edge when the active app has no window.
    private static func focusOnScreen(_ direction: Direction) -> Reply {
        let model = AppState.shared.displays
        model.reconcile()
        guard let main = model.focusedDisplay() else { return .error("no display") }
        let onSpace = Set(dinky_space_window_ids(main.currentSpaceID, false).map(\.uint32Value))
        let windows = windowList().filter { onSpace.contains($0.id) }
        var frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        if let workspace = AppState.shared.coordinator?.workspace(on: main) {
            frames = workspace.directionalFrames(frames, direction: direction)
        }
        let id: WindowID?
        if let front = windows.first(where: { $0.id == frontWindowID() }) {
            let candidates = frames.filter { $0.key != front.id }.map { ($0.key, $0.value) }
            id = directionalWindow(from: frames[front.id] ?? front.frame, candidates: candidates, direction: direction)
        } else {
            let candidates = frames.map { ($0.key, $0.value) }
            id = wrappedDirectionalWindow(from: main.visibleArea, candidates: candidates, direction: direction)
        }
        guard let id, let next = windows.first(where: { $0.id == id }) else {
            return .error("no window \(direction)")
        }
        if AppState.shared.coordinator?.model.windows[id] != nil { return focus(window: id) }
        focusWindow(pid: next.pid, id: next.id)
        MouseFollowFocus.shared.focusedByCommand(next.id)
        return .ok("focused window \(next.id) \(next.app)")
    }
}
