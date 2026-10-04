import Foundation
import DinkyLayout

struct DepartingTab {
    let window: Window
    let space: UInt64
    let expires: Date
}

// Native tabs: a newly shown window at the exact frame of a tile of its app is held out of the trees until
// it turns out to be the next tab of that tile (the tile's window is ordered out) or a window of its own.
extension Coordinator {
    /// Holds a newly shown window out of the tree if it may be the next tab of a tile of its app, and has not been
    /// held before. `settleTab` tiles it after 250 ms if the tile's window is still there.
    func holdAsTab(_ window: Window, in key: UInt64) -> Bool {
        if let old = departingTabs.first(where: { id, reserved in
            id != window.id && reserved.space == key && reserved.window.pid == window.pid
                && reserved.expires > Date() && reserved.window.frame.isClose(to: window.frame, within: 1)
                && workspaces[key]?.contains(id) == true
        }) {
            departingTabs[old.key] = nil
            edit(key) { $0.replace(old.key, with: window.id) }
            placements[window.id]!.space = key
            return true
        }
        guard !notTabs.contains(window.id), let tab = tab(replacedBy: window, in: key) else { return false }
        heldTabs[window.id] = tab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.settleTab(window.id) }
        return true
    }

    /// A tile a newly shown window may be taking over as the next tab of a native tab group: a window of the same
    /// app at exactly the tile's frame. AppKit shows a new tab by giving it the group's frame and ordering it in,
    /// then orders the previous tab out. But some apps (Ghostty, for one) open every new window at the previous
    /// window's frame, so the newcomer is held out of the tree until the tile's window is ordered out or
    /// `settleTab` gives up on it.
    private func tab(replacedBy window: Window, in key: UInt64) -> WindowID? {
        workspaces[key]?.windows.first { id in
            guard id != window.id, let other = model.windows[id] else { return false }
            return other.pid == window.pid && other.frame.isClose(to: window.frame, within: 1)
        }
    }

    /// When a tile's window is ordered out or closed just after a window of its app came in at its frame, that was
    /// a tab switch: the held new tab takes over the tile. False if no newcomer is held for this tile.
    func takeOverTile(of id: WindowID, in key: UInt64) -> Bool {
        guard let newcomer = heldTabs.first(where: { $0.value == id })?.key else { return false }
        heldTabs[newcomer] = nil
        edit(key) { $0.replace(id, with: newcomer) }
        placements[newcomer]!.space = key
        return true
    }

    /// Preserve the old tile long enough to recognize the hide-before-create event order.
    func reserveTab(_ window: Window, in key: UInt64) {
        guard departingTabs[window.id] == nil else { return }
        let expires = Date().addingTimeInterval(0.25)
        departingTabs[window.id] = DepartingTab(window: window, space: key, expires: expires)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.departingTabs[window.id]?.expires == expires else { return }
            self.departingTabs[window.id] = nil
            self.edit(key) { $0.remove(window.id) }
            self.flush()
        }
    }

    /// The tile's window stayed: the held newcomer was a window of its own, so it is tiled like any other.
    private func settleTab(_ id: WindowID) {
        guard heldTabs.removeValue(forKey: id) != nil, let window = model.windows[id] else { return }
        notTabs.insert(id)
        track(window)
        flush()
    }
}
