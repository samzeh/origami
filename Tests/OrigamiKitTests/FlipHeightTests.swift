import CoreGraphics
import Testing

@testable import OrigamiKit

@Suite("Choosing the coordinate flip reference")
struct FlipHeightTests {

    // Both systems anchor to the display at the origin; flipping against any other
    // display's height offsets every window vertically.

    @Test("uses the only display's height when there is one")
    func usesOnlyDisplayHeight() {
        let screens = [
            ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107), backingScale: 2)
        ]

        #expect(Geometry.flipHeight(screens: screens) == 1107)
    }

    @Test("uses the display at the origin, not merely the first one listed")
    func usesDisplayAtOrigin() {
        // AppKit does not guarantee the origin display comes first in the array.
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: 1710, y: 0, width: 2560, height: 1440), backingScale: 1
            ),
            ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107), backingScale: 2),
        ]

        #expect(Geometry.flipHeight(screens: screens) == 1107)
    }

    @Test("ignores a taller secondary display sitting at a negative origin")
    func ignoresTallerSecondaryDisplay() {
        let screens = [
            ScreenGeometry(
                frame: CGRect(x: -2560, y: -200, width: 2560, height: 1440), backingScale: 1
            ),
            ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1710, height: 1107), backingScale: 2),
        ]

        #expect(Geometry.flipHeight(screens: screens) == 1107)
    }

    @Test("falls back to the first display when none sits exactly at the origin")
    func fallsBackWhenNoDisplayAtOrigin() {
        let screens = [
            ScreenGeometry(frame: CGRect(x: 10, y: 10, width: 800, height: 600), backingScale: 1)
        ]

        #expect(Geometry.flipHeight(screens: screens) == 600)
    }

    @Test("reports zero height when there are no displays")
    func reportsZeroWithoutDisplays() {
        #expect(Geometry.flipHeight(screens: []) == 0)
    }
}
