import CoreGraphics
import Testing

@testable import OrigamiKit

@Suite("Capture image normalization")
struct ImageNormalizationTests {

    // A ScreenCaptureKit capture has a nil color space and hardware-padded rows;
    // normalization must produce a standard, tightly-packed, color-managed bitmap.

    private func paddedImage(width: Int, height: Int) -> CGImage {
        // Force a stride wider than width*4 to mimic ScreenCaptureKit's row padding,
        // and omit the color space, as ScreenCaptureKit does.
        let stride = (width * 4 + 63) & ~63  // round up to 64 bytes
        var pixels = [UInt8](repeating: 128, count: stride * height)
        let data = CFDataCreate(nil, &pixels, pixels.count)!
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    @Test("drops the row padding so the stride is exactly width times four")
    func dropsRowPadding() {
        let padded = paddedImage(width: 1000, height: 100)
        #expect(padded.bytesPerRow > 1000 * 4)  // precondition: the input is padded

        let normalized = ScreenCaptureKitCapturer.normalized(padded)

        #expect(normalized.bytesPerRow == 1000 * 4)
    }

    @Test("preserves the pixel dimensions")
    func preservesDimensions() {
        let normalized = ScreenCaptureKitCapturer.normalized(paddedImage(width: 640, height: 480))

        #expect(normalized.width == 640)
        #expect(normalized.height == 480)
    }

    @Test("gives the image a real color space")
    func givesColorSpace() {
        let normalized = ScreenCaptureKitCapturer.normalized(paddedImage(width: 320, height: 240))

        #expect(normalized.colorSpace != nil)
    }
}
