import Testing
import DinkyConfig

@Test func singleGroupWidthIsOptionalAndPositive() throws {
    #expect(Config.default.singleGroupMaxWidth == nil)
    #expect(try Config.parse("[single-group]\nmax-width = 1400").singleGroupMaxWidth == 1400)
    for width in [0, -10] {
        #expect(throws: ConfigError.self) { try Config.parse("[single-group]\nmax-width = \(width)") }
    }
}

@Test func singleGroupWidthPerDisplay() throws {
    let builtIn = Monitor(name: "Built-in Retina Display", isMain: false, count: 2)
    let studio = Monitor(name: "Studio Display XDR", isMain: true, count: 2)
    let config = try Config.parse("""
    [single-group]
    max-width = 2400

    [display.main]
    gaps.outer.top = 44

    [display.built-in]
    single-group.max-width = 1400
    """)
    #expect(config.singleGroupMaxWidth(for: builtIn) == 1400)
    #expect(config.singleGroupMaxWidth(for: studio) == 2400, "a display table without one keeps the general width")
    #expect(try Config.parse("[display.main]\nsingle-group.max-width = 1800").singleGroupMaxWidth(for: studio) == 1800,
            "a display can cap without a general width")
    for width in [0, -10] {
        #expect(throws: ConfigError.self) { try Config.parse("[display.main]\nsingle-group.max-width = \(width)") }
    }
    #expect(throws: ConfigError.self) { try Config.parse("[display.main]\nsingle-group.width = 1400") }
}
