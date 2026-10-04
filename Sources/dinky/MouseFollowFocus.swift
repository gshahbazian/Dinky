import AppKit
import DinkyPrivate

/// Command-scoped pointer movement, never a reaction to general focus notifications.
final class MouseFollowFocus {
    static let shared = MouseFollowFocus()
    private var generation = 0
    private var monitors: [Any] = []
    private var destination: UInt32?
    private var originalFocus: UInt32 = 0
    private var pointerAtRequest: CGPoint?
    private var pending: DispatchWorkItem?

    func begin() -> Int? {
        cancel()
        guard AppState.shared.config.mouseFollowsFocus, AppState.shared.enabled, !blocked else { return nil }
        originalFocus = AppState.shared.coordinator?.focusedWindow ?? frontWindowID()
        pointerAtRequest = CGEvent(source: nil)?.location
        if monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                               .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.mouseInput(event) }) {
                monitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.mouseInput(event)
                return event
            }) { monitors.append(local) }
        }
        return generation
    }

    func finish(_ request: Int, succeeded: Bool) {
        guard succeeded else { return cancel() }
        move(request, deadline: Date().addingTimeInterval(2), target: destination)
    }

    func focusedByCommand(_ id: UInt32) {
        guard pointerAtRequest != nil else { return }
        destination = id
    }

    private func mouseInput(_ event: NSEvent) {
        if event.type == .mouseMoved {
            guard let origin = pointerAtRequest, let current = CGEvent(source: nil)?.location,
                  hypot(current.x - origin.x, current.y - origin.y) > 2 else { return }
        }
        cancel()
    }

    private func cancel() {
        generation += 1
        pending?.cancel()
        pending = nil
        pointerAtRequest = nil
        destination = nil
    }

    private var blocked: Bool {
        if MissionControl.shared.active || NSEvent.pressedMouseButtons != 0 { return true }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let menu = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menu }
    }

    private func schedule(_ request: Int, deadline: Date, target: UInt32?) {
        let work = DispatchWorkItem { [weak self] in self?.move(request, deadline: deadline, target: target) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }

    private func move(_ request: Int, deadline: Date, target: UInt32?) {
        let state = AppState.shared
        guard request == generation, state.enabled, state.config.mouseFollowsFocus,
              Date() < deadline, !blocked else { return }
        if SpaceSwitcher.shared.switching {
            return schedule(request, deadline: deadline, target: nil)
        }
        let focused = state.coordinator?.focusedWindow ?? frontWindowID()
        let target = destination ?? target ?? focused
        if target != focused {
            guard focused == originalFocus else { return }
            return schedule(request, deadline: deadline, target: target)
        }
        if state.coordinator?.isAnimating(focused) == true {
            return schedule(request, deadline: deadline, target: target)
        }
        state.displays.reconcile()
        guard let display = state.displays.focusedDisplay() else { return }
        let rect: CGRect
        if let window = state.coordinator?.model.windows[focused], window.spaceID == display.currentSpaceID,
           window.isNormal, !window.isMinimized {
            rect = dinky_window_info(focused).frame
        } else {
            // Do not center the display for an untracked dialog or app window.
            guard let coordinator = state.coordinator,
                  !coordinator.model.windows.values.contains(where: {
                      $0.spaceID == display.currentSpaceID && $0.isNormal && !$0.isMinimized
                  }) else { return }
            rect = display.frame
        }
        guard let point = CGEvent(source: nil)?.location, !rect.isEmpty, !rect.contains(point) else { return }
        pointerAtRequest = nil
        CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: rect.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
        state.parkHoverAfterPointerMove()
    }
}
