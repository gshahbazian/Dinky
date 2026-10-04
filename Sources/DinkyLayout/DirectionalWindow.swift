import CoreGraphics

/// Floating windows use their actual frames, including when they overlap a tile.
public func directionalWindow(from: CGRect, candidates: [(WindowID, CGRect)], direction: Direction) -> WindowID? {
    let eligible = candidates.filter { _, to in
        let distance: CGFloat
        let overlaps: Bool
        switch direction {
        case .left, .right:
            distance = direction == .left ? from.midX - to.midX : to.midX - from.midX
            overlaps = min(from.maxY, to.maxY) > max(from.minY, to.minY)
        case .up, .down:
            distance = direction == .up ? from.midY - to.midY : to.midY - from.midY
            overlaps = min(from.maxX, to.maxX) > max(from.minX, to.minX)
        }
        return distance > 0 && overlaps
    }
    return eligible.min { a, b in
        let first = hypot(a.1.midX - from.midX, a.1.midY - from.midY)
        let second = hypot(b.1.midX - from.midX, b.1.midY - from.midY)
        if first == second { return a.0 < b.0 }
        return first < second
    }?.0
}

/// Wrap to the opposite spatial edge, including floating windows aligned with the source.
public func wrappedDirectionalWindow(from: CGRect, candidates: [(WindowID, CGRect)], direction: Direction) -> WindowID? {
    let aligned = candidates.filter { _, frame in
        direction.orientation == .horizontal
            ? min(from.maxY, frame.maxY) > max(from.minY, frame.minY)
            : min(from.maxX, frame.maxX) > max(from.minX, frame.minX)
    }
    return aligned.min { a, b in
        let first = direction.orientation == .horizontal ? a.1.midX : a.1.midY
        let second = direction.orientation == .horizontal ? b.1.midX : b.1.midY
        if first != second { return direction.isForward ? first < second : first > second }
        let firstDistance = hypot(a.1.midX - from.midX, a.1.midY - from.midY)
        let secondDistance = hypot(b.1.midX - from.midX, b.1.midY - from.midY)
        if firstDistance != secondDistance { return firstDistance < secondDistance }
        return a.0 < b.0
    }?.0
}

extension Workspace {
    /// Accordion peeks move with focus, so their centers cannot reliably express window order.
    public func directionalFrames(_ frames: [WindowID: CGRect], direction: Direction) -> [WindowID: CGRect] {
        var result = frames
        let layout = tiledLayout()
        func visit(_ container: Container, path: [Int]) {
            for (index, child) in container.children.enumerated() {
                if case .container(let nested) = child { visit(nested, path: path + [index]) }
            }
            guard container.mode == .accordion,
                  axisOfContainer(at: path, in: layout) == direction.orientation,
                  container.children.allSatisfy({ if case .window = $0 { return true }; return false }) else { return }
            let ids = container.children.flatMap(\.windows).filter { result[$0] != nil }
            guard ids.count > 1 else { return }
            let area = ids.compactMap { result[$0] }.reduce(CGRect.null) { $0.union($1) }
            let horizontal = direction.orientation == .horizontal
            let center = horizontal ? area.midX : area.midY
            let spacing = max(1, accordionPadding)
            for (index, id) in ids.enumerated() {
                guard var frame = result[id] else { continue }
                let position = center + (CGFloat(index) - CGFloat(ids.count - 1) / 2) * spacing
                if horizontal { frame.origin.x = position - frame.width / 2 }
                else { frame.origin.y = position - frame.height / 2 }
                result[id] = frame
            }
        }
        visit(root, path: [])
        return result
    }
}
