import Testing
@testable import NotchCore

@Suite("Package")
struct PackageSmokeTests {
    @Test("the NotchCore module builds and links")
    func moduleLinks() {
        #expect(MemoryLayout<Int>.size > 0)
    }
}
