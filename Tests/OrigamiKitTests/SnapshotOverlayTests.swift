import AppKit
import CoreGraphics
import Testing

@testable import OrigamiKit

/// A tiny real image, so the overlay is exercised with actual pixels rather than a
/// stand-in that could hide a scale or content bug.
private func makeImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func makeSnapshot(
    windowBounds: CGRect = CGRect(x: 100, y: 50, width: 400, height: 300),
    scale: CGFloat = 2
) -> WindowSnapshot {
    WindowSnapshot(
        image: makeImage(
            width: Int(windowBounds.width * scale),
            height: Int(windowBounds.height * scale)
        ),
        windowBounds: windowBounds,
        scale: scale,
        metrics: CaptureMetrics(enumerateWindows: .zero, buildFilter: .zero, captureImage: .zero)
    )
}

@Suite("Snapshot overlay", .serialized)
@MainActor
struct SnapshotOverlayTests {

    @Test("places the panel over the window, flipped into AppKit space")
    func placesPanelOverWindow() {
        let overlay = SnapshotOverlay()
        let snapshot = makeSnapshot(windowBounds: CGRect(x: 100, y: 50, width: 400, height: 300))

        overlay.show(snapshot, mainDisplayHeight: 1080)

        // Bottom edge is 50 + 300 = 350pt below the top, so 730pt up from the bottom.
        #expect(overlay.panel.frame == CGRect(x: 100, y: 730, width: 400, height: 300))
    }

    @Test("sizes the panel and snapshot to the window's own bounds")
    func sizesToWindowBounds() {
        let overlay = SnapshotOverlay()
        let snapshot = makeSnapshot(windowBounds: CGRect(x: 0, y: 0, width: 1465, height: 960))

        overlay.show(snapshot, mainDisplayHeight: 1080)

        #expect(overlay.panel.frame.size == CGSize(width: 1465, height: 960))
        #expect(overlay.snapshotSize == CGSize(width: 1465, height: 960))
    }

    @Test("swallows mouse events so the window underneath cannot be dragged")
    func swallowsMouseEvents() {
        // The window beneath must be unreachable; click-through would hand a drag to
        // the real titlebar still sitting underneath.
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)

        #expect(overlay.panel.ignoresMouseEvents == false)
    }

    @Test("never becomes the key window, so focus does not visibly move")
    func neverBecomesKeyWindow() {
        // Taking key status would change the menu bar and the active titlebar
        // appearance, which is exactly the kind of tell we are avoiding.
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)

        #expect(overlay.panel.canBecomeKey == false)
        #expect(overlay.panel.isKeyWindow == false)
    }

    @Test("floats above ordinary and floating windows")
    func floatsAboveOtherWindows() {
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)

        #expect(overlay.panel.level.rawValue > NSWindow.Level.floating.rawValue)
        #expect(overlay.panel.level.rawValue >= NSWindow.Level.statusBar.rawValue)
    }

    @Test("is transparent and borderless so rounded window corners are preserved")
    func isTransparentAndBorderless() {
        // A captured window carries its rounded corners as transparent pixels. An
        // opaque panel would fill them in with grey and square off the corners.
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)

        #expect(overlay.panel.isOpaque == false)
        #expect(overlay.panel.backgroundColor == .clear)
        #expect(overlay.panel.styleMask.contains(.borderless))
    }

    @Test("draws a window shadow, since the capture does not include one")
    func drawsItsOwnShadow() {
        // Measured: ScreenCaptureKit returns exactly the window rect with no shadow
        // padding, so the shadow has to come from the panel or it pops off at swap.
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)

        #expect(overlay.panel.hasShadow == true)
    }


    @Test("follows the window across every Space rather than one desktop")
    func followsWindowAcrossSpaces() {
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)

        #expect(overlay.panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(overlay.panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test("reports itself visible once shown and hidden once dismissed")
    func reportsVisibility() {
        let overlay = SnapshotOverlay()

        overlay.show(makeSnapshot(), mainDisplayHeight: 1080)
        #expect(overlay.isVisible == true)

        overlay.dismiss()
        #expect(overlay.isVisible == false)
    }

    @Test("tints the snapshot only when asked, for proving which layer you see")
    func tintsOnlyWhenAsked() {
        // A debug affordance: with the overlay pixel-identical to the window, you
        // otherwise cannot tell whether the swap happened at all.
        let plain = SnapshotOverlay()
        plain.show(makeSnapshot(), mainDisplayHeight: 1080)
        #expect(plain.tintView.isHidden == true)

        let tinted = SnapshotOverlay()
        tinted.show(makeSnapshot(), mainDisplayHeight: 1080, tinted: true)
        #expect(tinted.tintView.isHidden == false)
    }
}
