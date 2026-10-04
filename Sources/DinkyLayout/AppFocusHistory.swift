/// Each app's last confirmed focused window, independent of window stacking order.
public struct AppFocusHistory<App: Hashable, Identity: Equatable> {
    private var windows: [App: Identity] = [:]

    public init() {}

    public func lastFocused(for app: App) -> Identity? { windows[app] }

    public mutating func observe(_ identity: Identity, for app: App) {
        windows[app] = identity
    }

    public mutating func forget(_ identity: Identity) {
        windows = windows.filter { $0.value != identity }
    }
}
