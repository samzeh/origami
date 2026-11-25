import CoreGraphics
import Testing

@testable import OrigamiKit

@Suite("Core Graphics to AppKit coordinate conversion")
struct CoordinateConversionTests {

    // Core Graphics is top-left origin, AppKit bottom-left; converting needs the main
    // display's height, even for windows not on the main display.

    @Test("flips a window's origin into AppKit space on a single display")
    func flipsOriginOnSingleDisplay() {
        let cgBounds = CGRect(x: 100, y: 50, width: 400, height: 300)

        let frame = Geometry.appKitFrame(fromCGWindowBounds: cgBounds, mainDisplayHeight: 1080)

        // Bottom edge sits 50 + 300 = 350pt below the top, so 1080 - 350 = 730pt up.
        #expect(frame == CGRect(x: 100, y: 730, width: 400, height: 300))
    }

    @Test("keeps a window flush with the top of the display flush with the top")
    func keepsWindowFlushWithTop() {
        let cgBounds = CGRect(x: 0, y: 0, width: 800, height: 100)

        let frame = Geometry.appKitFrame(fromCGWindowBounds: cgBounds, mainDisplayHeight: 1080)

        #expect(frame.maxY == 1080)
    }

    @Test("maps a display mounted above the main one to positive AppKit y")
    func mapsDisplayAboveMain() {
        // A display stacked above the main one has negative y in Core Graphics space.
        let cgBounds = CGRect(x: 0, y: -800, width: 400, height: 300)

        let frame = Geometry.appKitFrame(fromCGWindowBounds: cgBounds, mainDisplayHeight: 1080)

        // 1080 - (-800 + 300) = 1580, i.e. above the main display's top edge.
        #expect(frame.origin.y == 1580)
    }

    @Test("passes a negative x through unchanged for a display to the left")
    func passesNegativeXThrough() {
        let cgBounds = CGRect(x: -1200, y: 100, width: 400, height: 300)

        let frame = Geometry.appKitFrame(fromCGWindowBounds: cgBounds, mainDisplayHeight: 1080)

        #expect(frame.origin.x == -1200)
    }
}

@Suite("Backing scale selection")
struct BackingScaleTests {

    // A Retina display reports a backing scale of 2. Capturing at the wrong scale
    // is what makes a snapshot look soft or half-size next to the real window.

    private let retinaMain = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), backingScale: 2
    )
    private let nonRetinaRight = ScreenGeometry(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), backingScale: 1
    )

    @Test("returns the scale of the display wholly containing the window")
    func returnsScaleOfContainingDisplay() {
        let window = CGRect(x: 200, y: 200, width: 400, height: 300)

        let scale = Geometry.backingScale(for: window, screens: [retinaMain, nonRetinaRight])

        #expect(scale == 2)
    }

    @Test("returns the secondary display's scale for a window living there")
    func returnsSecondaryDisplayScale() {
        let window = CGRect(x: 1600, y: 200, width: 400, height: 300)

        let scale = Geometry.backingScale(for: window, screens: [retinaMain, nonRetinaRight])

        #expect(scale == 1)
    }

    @Test("picks the display holding most of a straddling window")
    func picksMajorityDisplayWhenStraddling() {
        // 50pt on the retina display, 150pt on the non-retina one.
        let window = CGRect(x: 1390, y: 400, width: 200, height: 100)

        let scale = Geometry.backingScale(for: window, screens: [retinaMain, nonRetinaRight])

        #expect(scale == 1)
    }

    @Test("picks the retina display when it holds most of a straddling window")
    func picksRetinaWhenItHoldsMajority() {
        // 150pt on the retina display, 50pt on the non-retina one.
        let window = CGRect(x: 1290, y: 400, width: 200, height: 100)

        let scale = Geometry.backingScale(for: window, screens: [retinaMain, nonRetinaRight])

        #expect(scale == 2)
    }

    @Test("falls back to the first display for a window that intersects none")
    func fallsBackToFirstDisplay() {
        let window = CGRect(x: 9000, y: 9000, width: 100, height: 100)

        let scale = Geometry.backingScale(for: window, screens: [retinaMain, nonRetinaRight])

        #expect(scale == 2)
    }

    @Test("falls back to 1 when there are no displays at all")
    func fallsBackToOneWithoutDisplays() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)

        let scale = Geometry.backingScale(for: window, screens: [])

        #expect(scale == 1)
    }
}

@Suite("Pixel dimensions for capture")
struct PixelSizeTests {

    // ScreenCaptureKit wants integer pixel dimensions, not points.

    @Test("doubles point dimensions on a 2x display")
    func doublesOnRetina() {
        let size = Geometry.pixelSize(ofPointSize: CGSize(width: 400, height: 300), scale: 2)

        #expect(size == PixelSize(width: 800, height: 600))
    }

    @Test("passes point dimensions through on a 1x display")
    func passesThroughOnNonRetina() {
        let size = Geometry.pixelSize(ofPointSize: CGSize(width: 400, height: 300), scale: 1)

        #expect(size == PixelSize(width: 400, height: 300))
    }

    @Test("rounds fractional point dimensions up to whole pixels")
    func roundsFractionalDimensions() {
        // Window frames are not always on whole points; truncating here crops a
        // sliver off the right and bottom edges of the snapshot.
        let size = Geometry.pixelSize(ofPointSize: CGSize(width: 400.2, height: 300.6), scale: 2)

        #expect(size == PixelSize(width: 801, height: 602))
    }

    @Test("never reports a zero dimension for a degenerate window")
    func neverReportsZeroDimension() {
        let size = Geometry.pixelSize(ofPointSize: CGSize(width: 0, height: 0), scale: 2)

        #expect(size == PixelSize(width: 1, height: 1))
    }
}
