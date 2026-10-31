import CoreGraphics
import Testing
@testable import DinkyLayout

@Test func chromeMessagesAndNotesShareOneFocusCycle() {
    let windows: [(WindowID, CGRect)] = [
        (1, CGRect(x: 16, y: 414, width: 695, height: 523)),
        (2, CGRect(x: 56, y: 41, width: 1400, height: 933)),
        (3, CGRect(x: 854, y: 33, width: 658, height: 320)),
    ]
    for (direction, order) in [(Direction.right, [1, 2, 3]), (.left, [3, 2, 1]), (.down, [3, 2, 1]), (.up, [1, 2, 3])] {
        for index in order.indices {
            let source = windows.first { $0.0 == WindowID(order[index]) }!
            let candidates = windows.filter { $0.0 != source.0 }
            let next = directionalWindow(from: source, candidates: candidates, direction: direction)
            if index == order.count - 1 {
                #expect(next == nil)
                #expect(wrappedDirectionalWindow(candidates: candidates, direction: direction) == WindowID(order[0]))
                continue
            }
            #expect(next == WindowID(order[index + 1]))
        }
    }
}

@Test(arguments: [Direction.left, .right, .up, .down])
func focusVisitsEveryWindowAndReversesEvenWithIdenticalCenters(direction: Direction) {
    let windows: [(WindowID, CGRect)] = [
        (1, CGRect(x: 0, y: 0, width: 100, height: 100)),
        (2, CGRect(x: 0, y: 200, width: 100, height: 100)),
        (3, CGRect(x: 200, y: 0, width: 100, height: 100)),
        (4, CGRect(x: 200, y: 200, width: 100, height: 100)),
        (5, CGRect(x: 0, y: 0, width: 100, height: 100)),
        (6, CGRect(x: -50, y: -50, width: 200, height: 200)),
    ]
    func step(_ source: (WindowID, CGRect), direction: Direction) -> WindowID? {
        let candidates = windows.reversed().filter { $0.0 != source.0 }
        return directionalWindow(from: source, candidates: candidates, direction: direction)
            ?? wrappedDirectionalWindow(candidates: candidates, direction: direction)
    }
    for start in windows {
        var current = start
        var visited: Set<WindowID> = []
        for _ in windows.indices {
            #expect(visited.insert(current.0).inserted)
            guard let nextID = step(current, direction: direction),
                  let next = windows.first(where: { $0.0 == nextID }) else {
                Issue.record("Focus stopped before completing the cycle")
                return
            }
            #expect(step(next, direction: direction.opposite) == current.0)
            current = next
        }
        #expect(current.0 == start.0)
        #expect(visited == Set(windows.map(\.0)))
    }
}

@Test func diagonallySeparatedFloatingWindowsRemainReachable() {
    let notes = CGRect(x: 32, y: 402, width: 700, height: 526)
    let messages = CGRect(x: 854, y: 33, width: 658, height: 320)
    #expect(directionalWindow(from: (1, notes), candidates: [(2, messages)], direction: .right) == 2)
    #expect(directionalWindow(from: (2, messages), candidates: [(1, notes)], direction: .left) == 1)
    #expect(directionalWindow(from: (1, notes), candidates: [(2, messages)], direction: .up) == 2)
    #expect(directionalWindow(from: (2, messages), candidates: [(1, notes)], direction: .down) == 1)
    #expect(directionalWindow(from: (1, notes), candidates: [(2, messages)], direction: .left) == nil)
    #expect(directionalWindow(from: (2, messages), candidates: [(1, notes)], direction: .up) == nil)
    #expect(wrappedDirectionalWindow(candidates: [(2, messages)], direction: .left) == 2)
    #expect(wrappedDirectionalWindow(candidates: [(1, notes)], direction: .right) == 1)
    #expect(wrappedDirectionalWindow(candidates: [(2, messages)], direction: .down) == 2)
    #expect(wrappedDirectionalWindow(candidates: [(1, notes)], direction: .up) == 1)
}

@Test(arguments: [Direction.left, .right, .up, .down])
func floatingFocusUsesAxisOrderBeforeAlignment(direction: Direction) {
    let from = CGRect(x: 0, y: 0, width: 100, height: 100)
    let offset: CGFloat = direction.isForward ? 1 : -1
    let horizontal = direction.orientation == .horizontal
    let aligned = CGRect(x: horizontal ? offset * 400 : 0, y: horizontal ? 0 : offset * 400, width: 100, height: 100)
    let diagonal = CGRect(x: horizontal ? offset * 110 : 100, y: horizontal ? 100 : offset * 110, width: 100, height: 100)
    #expect(directionalWindow(from: (1, from), candidates: [(2, aligned), (3, diagonal)], direction: direction) == 3)
    #expect(directionalWindow(from: (1, from), candidates: [(3, diagonal)], direction: direction) == 3)
}

@Test func diagonalFocusUsesStableSpatialOrder() {
    let from = CGRect(x: 0, y: 0, width: 100, height: 100)
    let near = CGRect(x: 150, y: 150, width: 100, height: 100)
    let far = CGRect(x: 300, y: 300, width: 100, height: 100)
    let candidates: [(WindowID, CGRect)] = [(4, far), (3, near), (2, near)]
    #expect(directionalWindow(from: (1, from), candidates: candidates, direction: .right) == 2)
    #expect(directionalWindow(from: (1, from), candidates: candidates.reversed(), direction: .down) == 2)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .right) == 2)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .left) == 4)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .down) == 2)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .up) == 4)
}

@Test func floatingWindowOverlappingTilesIsReachable() {
    let chrome = CGRect(x: 8, y: 41, width: 744, height: 933)
    let ghostty = CGRect(x: 760, y: 41, width: 744, height: 933)
    let chat = CGRect(x: 121, y: 33, width: 1326, height: 729)
    #expect(directionalWindow(from: (1, chrome), candidates: [(164, chat)], direction: .right) == 164)
    #expect(directionalWindow(from: (2, ghostty), candidates: [(164, chat)], direction: .left) == 164)
    #expect(directionalWindow(from: (1, chrome), candidates: [(164, chat)], direction: .up) == 164)
    #expect(directionalWindow(from: (1, chrome), candidates: [(164, chat)], direction: .down) == nil)
}

@Test func floatingFocusIncludesDiagonalWindowInAxisOrder() {
    let from = CGRect(x: 0, y: 0, width: 100, height: 100)
    let near = CGRect(x: 150, y: 0, width: 100, height: 100)
    let far = CGRect(x: 300, y: 0, width: 100, height: 100)
    let diagonal = CGRect(x: 110, y: 200, width: 100, height: 100)
    #expect(directionalWindow(from: (1, from), candidates: [(3, far), (2, near), (4, diagonal)], direction: .right) == 4)
    #expect(directionalWindow(from: (1, from), candidates: [], direction: .right) == nil)
}

@Test func accordionEdgeWrapIncludesFloatingMessages() {
    let left = CGRect(x: 56, y: 41, width: 1370, height: 933)
    let right = CGRect(x: 86, y: 41, width: 1370, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    #expect(wrappedDirectionalWindow(candidates: [(2, right), (3, messages)], direction: .left) == 3)
    #expect(wrappedDirectionalWindow(candidates: [(1, left), (3, messages)], direction: .right) == 1)
    let unaligned = CGRect(x: 1600, y: 1100, width: 300, height: 200)
    #expect(wrappedDirectionalWindow(candidates: [(2, right), (4, unaligned)], direction: .left) == 4)
}

@Test func nearbyRightTileWinsOverFloatingMessages() {
    let left = CGRect(x: 56, y: 41, width: 696, height: 933)
    let right = CGRect(x: 760, y: 41, width: 696, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    #expect(directionalWindow(from: (1, left), candidates: [(2, right), (3, messages)], direction: .right) == 2)
    #expect(directionalWindow(from: (2, right), candidates: [(1, left), (3, messages)], direction: .right) == 3)
}

@Test func accordionPeeksNavigateByActualLocation() {
    let left = CGRect(x: 56, y: 41, width: 1370, height: 933)
    let right = CGRect(x: 86, y: 41, width: 1370, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    #expect(directionalWindow(from: (1, left), candidates: [(2, right), (3, messages)], direction: .right) == 2)
    #expect(directionalWindow(from: (2, right), candidates: [(1, left), (3, messages)], direction: .left) == 1)
    #expect(directionalWindow(from: (2, right), candidates: [(1, left), (3, messages)], direction: .right) == 3)
}

@Test func enteringWithoutFocusedWindowUsesOppositeScreenEdge() {
    let left = CGRect(x: 8, y: 41, width: 744, height: 933)
    let right = CGRect(x: 760, y: 41, width: 744, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    let candidates: [(WindowID, CGRect)] = [(1, left), (2, right), (3, messages)]
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .right) == 1)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .left) == 3)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .down) == 3)
    #expect(wrappedDirectionalWindow(candidates: candidates, direction: .up) == 2)
    #expect(wrappedDirectionalWindow(candidates: [], direction: .right) == nil)
}

@Test func accordionNavigationFollowsOrderDespiteCollapsedPeeks() {
    var workspace = Workspace(bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))
    workspace.root = Container(.horizontal, .accordion, [.window(1), .window(2), .window(3)])
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    for active in [WindowID(1), 2, 3] {
        workspace.focus(active)
        var actual = workspace.tiledLayout().frames
        actual[4] = messages
        for direction in [Direction.left, .right] {
            let frames = workspace.directionalFrames(actual, direction: direction)
            for (source, target) in direction == .right ? [(1, 2), (2, 3), (3, 4)] : [(3, 2), (2, 1)] {
                let candidates = frames.filter { $0.key != WindowID(source) }.map { ($0.key, $0.value) }
                #expect(directionalWindow(from: (WindowID(source), frames[WindowID(source)]!), candidates: candidates, direction: direction) == WindowID(target))
            }
            #expect(frames[4] == messages)
        }
    }
}
