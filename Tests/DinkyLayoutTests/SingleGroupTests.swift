import CoreGraphics
import Testing
@testable import DinkyLayout

@Test func singleGroupCentersWithinGapsAndRestoresAfterSecondWindow() {
    var ws = workspace(1, bounds: rect(100, 50, 2400, 1000), gaps: Gaps(all: 8))
    ws.singleGroupMaxWidth = 1400
    let centered = rect(600, 58, 1400, 984)
    #expect(ws.layout().frames[1] == centered)
    ws.insert(2)
    #expect(ws.layout().frames[1] != centered)
    ws.remove(2)
    #expect(ws.layout().frames[1] == centered)
    ws.toggleFullscreen()
    #expect(ws.layout().frames[1] == rect(108, 58, 2384, 984))
    ws.toggleFullscreen()
    #expect(ws.layout().frames[1] == centered)
}

@Test func singleGroupCapFitsSmallDisplaysAndHonorsMinimums() {
    var ws = workspace(1, bounds: rect(0, 0, 1000, 600))
    ws.singleGroupMaxWidth = 1400
    #expect(ws.layout().frames[1] == rect(0, 0, 1000, 600))
    ws.bounds = rect(0, 0, 2400, 1000)
    ws.minimumSizes[1] = rect(0, 0, 1600, 500).size
    #expect(ws.layout().frames[1] == rect(400, 0, 1600, 1000))
    ws.singleGroupMaxWidth = nil
    #expect(ws.layout().frames[1] == rect(0, 0, 2400, 1000))
}

@Test func singleGroupCapLeavesFixedGridUntouchedAndSupportsAccordion() {
    var fixed = workspace(1, bounds: rect(0, 0, 2400, 1000), algorithm: .fixed(rows: 1, columns: 2, expand: .columns))
    let before = fixed.layout()
    fixed.singleGroupMaxWidth = 1400
    #expect(fixed.layout() == before)
    var accordion = workspace(1, bounds: rect(0, 0, 2400, 1000), algorithm: .dwindle(.accordion))
    accordion.singleGroupMaxWidth = 1400
    #expect(accordion.layout().frames[1] == rect(500, 0, 1400, 1000))
}

@Test func accordionGroupCentersIncludingPeeks() {
    var ws = workspace(2, bounds: rect(100, 50, 2400, 1000), gaps: Gaps(all: 8), algorithm: .dwindle(.accordion))
    ws.singleGroupMaxWidth = 1400
    let frames = ws.layout().frames
    #expect(frames[1] == rect(600, 58, 1370, 984))
    #expect(frames[2] == rect(630, 58, 1370, 984))
    ws.insert(3)
    #expect(ws.layout().frames.values.reduce(CGRect.null) { $0.union($1) } == rect(600, 58, 1400, 984))
    ws.toggleFullscreen()
    #expect(ws.layout().frames[ws.focused!] == rect(108, 58, 2384, 984))
}

@Test func nestedStackQualifiesButSplitAndSecondGroupDoNot() {
    var ws = workspace(2, bounds: rect(0, 0, 2400, 1000))
    ws.singleGroupMaxWidth = 1400
    let stack = Node.container(Container(.horizontal, .accordion, [.window(1), .window(2)]))
    ws.root = Container(.horizontal, .tiles, [.container(Container(.vertical, .tiles, [stack]))])
    #expect(ws.layout().frames.values.reduce(CGRect.null) { $0.union($1) } == rect(500, 0, 1400, 1000))
    ws.root = Container(.horizontal, .tiles, [stack, .window(3)])
    #expect(ws.layout().frames.values.reduce(CGRect.null) { $0.union($1) } == ws.bounds)
    ws.root = Container(.horizontal, .accordion, [.container(Container(.horizontal, .tiles, [.window(1), .window(2)])), .window(3)])
    #expect(ws.layout().frames.values.reduce(CGRect.null) { $0.union($1) } == ws.bounds)
}

@Test func groupCapHonorsHorizontalVerticalAndAutoMinimums() {
    var ws = workspace(2, bounds: rect(0, 0, 2400, 1000), algorithm: .dwindle(.accordion))
    ws.singleGroupMaxWidth = 1400
    ws.minimumSizes[1] = rect(0, 0, 1600, 500).size
    #expect(ws.layout().frames[1]?.width == 1600)
    #expect(ws.layout().frames.values.reduce(CGRect.null) { $0.union($1) } == rect(385, 0, 1630, 1000))
    ws.root.orientation = .vertical
    #expect(ws.layout().frames[1]?.width == 1600)
    ws.root.orientation = .auto
    #expect(ws.layout().frames[1]?.width == 1600)
    ws.bounds = rect(0, 0, 1000, 1800)
    #expect(ws.layout().frames[1]?.width == 1000)
}
