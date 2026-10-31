import CoreGraphics

/// Step through a consistent spatial order so repeated focus commands cannot skip windows.
public func directionalWindow(from: (WindowID, CGRect), candidates: [(WindowID, CGRect)], direction: Direction) -> WindowID? {
    let ordered = (candidates + [from]).sorted { spatiallyPrecedes($0, $1, direction: direction) }
    guard let index = ordered.firstIndex(where: { $0.0 == from.0 }), index + 1 < ordered.count else { return nil }
    return ordered[index + 1].0
}

/// Wrap to the first window in the same order used for directional focus.
public func wrappedDirectionalWindow(candidates: [(WindowID, CGRect)], direction: Direction) -> WindowID? {
    candidates.min { spatiallyPrecedes($0, $1, direction: direction) }?.0
}

private func spatiallyPrecedes(_ a: (WindowID, CGRect), _ b: (WindowID, CGRect), direction: Direction) -> Bool {
    let horizontal = direction.orientation == .horizontal
    let first = horizontal ? a.1.midX : a.1.midY
    let second = horizontal ? b.1.midX : b.1.midY
    if first != second { return direction.isForward ? first < second : first > second }
    let firstCross = horizontal ? a.1.midY : a.1.midX
    let secondCross = horizontal ? b.1.midY : b.1.midX
    if firstCross != secondCross { return direction.isForward ? firstCross < secondCross : firstCross > secondCross }
    return direction.isForward ? a.0 < b.0 : a.0 > b.0
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
