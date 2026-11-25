import CoreGraphics
import Foundation

/// A display, described the way AppKit describes it: origin at the bottom-left of
/// the main display, y growing upward.
public struct ScreenGeometry: Equatable, Sendable {
    public let frame: CGRect
    public let backingScale: CGFloat

    public init(frame: CGRect, backingScale: CGFloat) {
        self.frame = frame
        self.backingScale = backingScale
    }
}

/// Integer pixel dimensions. ScreenCaptureKit is configured in pixels, not points.
public struct PixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Pure coordinate math. No system calls, so all of it is directly testable.
public enum Geometry {

    /// Converts top-left-origin Core Graphics window bounds into a bottom-left-origin
    /// AppKit frame, flipping against the main display's height.
    public static func appKitFrame(
        fromCGWindowBounds bounds: CGRect,
        mainDisplayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: bounds.origin.x,
            y: mainDisplayHeight - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    /// Height to flip coordinates against: that of the display at the origin, which
    /// both coordinate systems are anchored to. Found by origin, not array position.
    public static func flipHeight(screens: [ScreenGeometry]) -> CGFloat {
        if let atOrigin = screens.first(where: { $0.frame.origin == .zero }) {
            return atOrigin.frame.height
        }
        return screens.first?.frame.height ?? 0
    }

    /// The backing scale of whichever display holds most of the window. Falls back
    /// to the first display when it overlaps none, and to 1 when there are none.
    public static func backingScale(for frame: CGRect, screens: [ScreenGeometry]) -> CGFloat {
        guard let fallback = screens.first else { return 1 }

        let best = screens.max { overlapArea(frame, $0.frame) < overlapArea(frame, $1.frame) }

        guard let best, overlapArea(frame, best.frame) > 0 else { return fallback.backingScale }
        return best.backingScale
    }

    /// Point dimensions converted to whole pixels, rounding up so fractional-point
    /// frames don't shave a hairline off the snapshot's right and bottom edges.
    public static func pixelSize(ofPointSize size: CGSize, scale: CGFloat) -> PixelSize {
        PixelSize(
            width: max(1, Int(ceil(size.width * scale))),
            height: max(1, Int(ceil(size.height * scale)))
        )
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull, !overlap.isEmpty else { return 0 }
        return overlap.width * overlap.height
    }
}
