import CoreGraphics
import Testing
@testable import DinkyLayout

@Test func floatingWindowOverlappingTilesIsReachable() {
    let chrome = CGRect(x: 8, y: 41, width: 744, height: 933)
    let ghostty = CGRect(x: 760, y: 41, width: 744, height: 933)
    let chat = CGRect(x: 121, y: 33, width: 1326, height: 729)
    #expect(directionalWindow(from: chrome, candidates: [(164, chat)], direction: .right) == 164)
    #expect(directionalWindow(from: ghostty, candidates: [(164, chat)], direction: .left) == 164)
    #expect(directionalWindow(from: chrome, candidates: [(164, chat)], direction: .up) == 164)
    #expect(directionalWindow(from: chrome, candidates: [(164, chat)], direction: .down) == nil)
}

@Test func floatingFocusChoosesNearestAlignedWindow() {
    let from = CGRect(x: 0, y: 0, width: 100, height: 100)
    let near = CGRect(x: 150, y: 0, width: 100, height: 100)
    let far = CGRect(x: 300, y: 0, width: 100, height: 100)
    let diagonal = CGRect(x: 110, y: 200, width: 100, height: 100)
    #expect(directionalWindow(from: from, candidates: [(3, far), (2, near), (4, diagonal)], direction: .right) == 2)
    #expect(directionalWindow(from: from, candidates: [], direction: .right) == nil)
}

@Test func accordionEdgeWrapIncludesFloatingMessages() {
    let left = CGRect(x: 56, y: 41, width: 1370, height: 933)
    let right = CGRect(x: 86, y: 41, width: 1370, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    #expect(wrappedDirectionalWindow(from: left, candidates: [(2, right), (3, messages)], direction: .left) == 3)
    #expect(wrappedDirectionalWindow(from: right, candidates: [(1, left), (3, messages)], direction: .right) == 1)
    let unaligned = CGRect(x: 1600, y: 1100, width: 300, height: 200)
    #expect(wrappedDirectionalWindow(from: left, candidates: [(2, right), (4, unaligned)], direction: .left) == 2)
}

@Test func nearbyRightTileWinsOverFloatingMessages() {
    let left = CGRect(x: 56, y: 41, width: 696, height: 933)
    let right = CGRect(x: 760, y: 41, width: 696, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    #expect(directionalWindow(from: left, candidates: [(2, right), (3, messages)], direction: .right) == 2)
    #expect(directionalWindow(from: right, candidates: [(1, left), (3, messages)], direction: .right) == 3)
}

@Test func accordionPeeksNavigateByActualLocation() {
    let left = CGRect(x: 56, y: 41, width: 1370, height: 933)
    let right = CGRect(x: 86, y: 41, width: 1370, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    #expect(directionalWindow(from: left, candidates: [(2, right), (3, messages)], direction: .right) == 2)
    #expect(directionalWindow(from: right, candidates: [(1, left), (3, messages)], direction: .left) == 1)
    #expect(directionalWindow(from: right, candidates: [(1, left), (3, messages)], direction: .right) == 3)
}

@Test func enteringWithoutFocusedWindowUsesOppositeScreenEdge() {
    let screen = CGRect(x: 0, y: 33, width: 1512, height: 949)
    let left = CGRect(x: 8, y: 41, width: 744, height: 933)
    let right = CGRect(x: 760, y: 41, width: 744, height: 933)
    let messages = CGRect(x: 880, y: 33, width: 632, height: 533)
    let candidates: [(WindowID, CGRect)] = [(1, left), (2, right), (3, messages)]
    #expect(wrappedDirectionalWindow(from: screen, candidates: candidates, direction: .right) == 1)
    #expect(wrappedDirectionalWindow(from: screen, candidates: candidates, direction: .left) == 3)
    #expect(wrappedDirectionalWindow(from: screen, candidates: candidates, direction: .down) == 3)
    #expect(wrappedDirectionalWindow(from: screen, candidates: candidates, direction: .up) == 1)
    #expect(wrappedDirectionalWindow(from: screen, candidates: [], direction: .right) == nil)
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
                #expect(directionalWindow(from: frames[WindowID(source)]!, candidates: candidates, direction: direction) == WindowID(target))
            }
            #expect(frames[4] == messages)
        }
    }
}
