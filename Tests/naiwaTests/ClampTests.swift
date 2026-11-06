import AppKit
import Testing
@testable import naiwa

struct ClampTests {
    let vf = NSRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func fitsUnchanged() {
        let r = NSRect(x: 600, y: 25, width: 200, height: 200)
        #expect(Pet.clamp(r, into: vf) == r)
    }

    @Test func topOverflowMovesDown() {
        let r = NSRect(x: 600, y: 800, width: 260, height: 260)
        #expect(Pet.clamp(r, into: vf) == NSRect(x: 600, y: 640, width: 260, height: 260))
    }

    @Test func rightOverflowMovesLeft() {
        let r = NSRect(x: 1300, y: 25, width: 260, height: 260)
        #expect(Pet.clamp(r, into: vf) == NSRect(x: 1180, y: 25, width: 260, height: 260))
    }

    @Test func leftBottomOverflowMovesIn() {
        let r = NSRect(x: -50, y: 0, width: 200, height: 200)
        #expect(Pet.clamp(r, into: vf) == NSRect(x: 0, y: 25, width: 200, height: 200))
    }

    @Test func largerThanScreenCentersAndSitsOnBottom() {
        let small = NSRect(x: 100, y: 100, width: 200, height: 150)
        let r = NSRect(x: 900, y: 120, width: 260, height: 260)
        #expect(Pet.clamp(r, into: small) == NSRect(x: 70, y: 100, width: 260, height: 260))
    }
}
