import Testing
import DinkyCommands
import DinkyConfig

@Test func mouseFollowOnlyAppliesToNavigation() throws {
    for line in ["focus-back-and-forth", "focus left", "workspace 2", "workspace-back-and-forth", "focus-monitor next", "move-window-to-workspace 2 --follow"] {
        #expect(try Command.parse(line).followsMouse)
    }
    for line in ["layout floating", "move left", "resize smart +50", "move-window-to-workspace 2", "reload-config"] {
        #expect(try !Command.parse(line).followsMouse)
    }
    #expect(!Config.default.mouseFollowsFocus)
    #expect(try Config.parse("[mouse-follows-focus]\nenabled = true\n").mouseFollowsFocus)
}
