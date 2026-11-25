import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A captured window, plus the geometry needed to lay it back over the screen.
public struct WindowSnapshot: @unchecked Sendable {
    public let image: CGImage

    /// The window's own bounds (points, Core Graphics coordinates), from
    /// `CGWindowListCopyWindowInfo`. This is what the overlay is positioned with.
    public let windowBounds: CGRect

    /// Pixels per point of the captured image.
    public let scale: CGFloat
    public let metrics: CaptureMetrics

    public init(image: CGImage, windowBounds: CGRect, scale: CGFloat, metrics: CaptureMetrics) {
        self.image = image
        self.windowBounds = windowBounds
        self.scale = scale
        self.metrics = metrics
    }

    public var pixelSize: PixelSize {
        PixelSize(width: image.width, height: image.height)
    }
}

/// Where the time goes. The PRD budgets roughly a second from keypress to the
/// animation starting, and window enumeration is the step most likely to spend it.
public struct CaptureMetrics: Sendable {
    public let enumerateWindows: Duration
    public let buildFilter: Duration
    public let captureImage: Duration

    public var total: Duration { enumerateWindows + buildFilter + captureImage }

    public init(enumerateWindows: Duration, buildFilter: Duration, captureImage: Duration) {
        self.enumerateWindows = enumerateWindows
        self.buildFilter = buildFilter
        self.captureImage = captureImage
    }
}

public enum CaptureError: Error, Equatable {
    /// Screen Recording permission has not been granted.
    case permissionDenied
    /// The window disappeared between being located and being captured.
    case windowNoLongerExists(CGWindowID)
}

public protocol WindowCapturing: Sendable {
    /// Takes the whole `WindowInfo` (not just an id) so the window's own bounds are
    /// used to place the result rather than re-derived from ScreenCaptureKit.
    func capture(_ window: WindowInfo) async throws -> WindowSnapshot
}

/// One-shot window capture via ScreenCaptureKit. `captureImage` takes a single frame
/// without a stream, keeping the app idle until Cmd+Q.
public struct ScreenCaptureKitCapturer: WindowCapturing {

    public init() {}

    public func capture(_ window: WindowInfo) async throws -> WindowSnapshot {
        let clock = ContinuousClock()
        let windowID = window.id

        // Check permission first, so a denied grant reports the real reason rather
        // than surfacing as "window not found".
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }

        var content: SCShareableContent!
        let enumerateWindows = try await clock.measure {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        }

        var filter: SCContentFilter!
        let buildFilter = try clock.measure {
            guard let captured = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNoLongerExists(windowID)
            }
            // A "desktop independent" window filter captures just this window,
            // with nothing behind it and nothing in front of it.
            filter = SCContentFilter(desktopIndependentWindow: captured)
        }

        let configuration = SCStreamConfiguration()
        let scale = filter.pointPixelScale
        let pixels = Geometry.pixelSize(
            ofPointSize: filter.contentRect.size,
            scale: CGFloat(scale)
        )
        configuration.width = pixels.width
        configuration.height = pixels.height
        // Capture at full pixel density so the snapshot isn't soft next to the window.
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.showsCursor = false
        // Exclude the shadow: including it packs shadow-plus-window into the
        // window-sized output, shrinking the content. The overlay draws its own.
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = true

        var image: CGImage!
        let captureImage = try await clock.measure {
            let raw = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            image = Self.normalized(raw)
        }

        return WindowSnapshot(
            image: image,
            windowBounds: window.bounds,
            scale: CGFloat(scale),
            metrics: CaptureMetrics(
                enumerateWindows: enumerateWindows,
                buildFilter: buildFilter,
                captureImage: captureImage
            )
        )
    }

    /// Redraws the capture into a standard sRGB bitmap: SCK returns an IOSurface image
    /// with a nil color space and padded rows, which this normalizes before use.
    static func normalized(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return image
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
