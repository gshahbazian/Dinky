import Testing
@testable import DinkyLayout

struct AppFocusHistoryTests {
    @Test func remembersEachAppAcrossSwitches() {
        var history = AppFocusHistory<String, Int>()
        history.observe(77, for: "chrome")
        history.observe(5128, for: "ghostty")
        #expect(history.lastFocused(for: "chrome") == 77)
        #expect(history.lastFocused(for: "ghostty") == 5128)
        history.observe(6604, for: "chrome")
        #expect(history.lastFocused(for: "chrome") == 6604)
        #expect(history.lastFocused(for: "ghostty") == 5128)
    }

    @Test func closingAnOlderWindowKeepsTheLatest() {
        var history = AppFocusHistory<String, Int>()
        history.observe(77, for: "chrome")
        history.observe(6604, for: "chrome")
        history.forget(77)
        #expect(history.lastFocused(for: "chrome") == 6604)
        history.forget(6604)
        #expect(history.lastFocused(for: "chrome") == nil)
    }
}
