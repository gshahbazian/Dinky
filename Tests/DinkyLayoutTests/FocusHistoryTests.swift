import Testing
@testable import DinkyLayout

@Test func focusHistoryTogglesAndIgnoresDuplicateEvents() {
    var history = FocusHistory<Int>()
    #expect(history.previous == nil)
    history.observe(1)
    history.observe(1)
    #expect(history.previous == nil)
    history.observe(2)
    history.observe(2)
    #expect(history.previous == 1)
    history.observe(history.previous!)
    #expect(history.current == 1)
    #expect(history.previous == 2)
    history.observe(history.previous!)
    #expect(history.current == 2)
    #expect(history.previous == 1)
    history.forget(1)
    #expect(history.previous == nil)
    history.forget(2)
    #expect(history.current == nil)
}
