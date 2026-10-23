import Testing
@testable import DateCore

@Test func paletteAvailable() {
    let rest = PaletteColor.available(taken: [.sky])
    #expect(rest.count == 5)
    #expect(!rest.contains(.sky))
    #expect(PaletteColor.pink.hex == "#F7C6D3")
}
