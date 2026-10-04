/// The last two distinct confirmed windows. Repeated notifications do not change history.
public struct FocusHistory<Identity: Equatable> {
    public private(set) var current: Identity?
    public private(set) var previous: Identity?

    public init() {}

    public mutating func observe(_ identity: Identity) {
        guard identity != current else { return }
        previous = current
        current = identity
    }

    public mutating func forget(_ identity: Identity) {
        if current == identity { current = nil }
        if previous == identity { previous = nil }
    }
}
