import Testing
import DinkyConfig

@Test func centeredScrollingIsOptional() throws {
    #expect(!Config.default.scrolling.centerFocusedColumn)
    #expect(try Config.parse("[scrolling]\ncenter-focused-column = true").scrolling.centerFocusedColumn)
}
