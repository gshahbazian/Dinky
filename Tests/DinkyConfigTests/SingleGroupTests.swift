import Testing
import DinkyConfig

@Test func singleGroupWidthIsOptionalAndPositive() throws {
    #expect(Config.default.singleGroupMaxWidth == nil)
    #expect(try Config.parse("[single-group]\nmax-width = 1400").singleGroupMaxWidth == 1400)
    for width in [0, -10] {
        #expect(throws: ConfigError.self) { try Config.parse("[single-group]\nmax-width = \(width)") }
    }
}
