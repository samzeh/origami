import AppKit
import OrigamiKit
import QuartzCore

/// Throwaway spike: folds the right half of a snapshot onto the left, to prove the
/// CATransformLayer nesting, hinge pivot, perspective and blank backface.
@MainActor
enum FoldSpike {

    /// The window's own average colour, so a dark app folds into dark paper rather
    /// than a jarring white. Drawing into a 1x1 bitmap averages the whole image.
    static func paperColor(for image: CGImage, shade: CGFloat = 1) -> CGColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return CGColor(gray: 0.95, alpha: 1) }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CGColor(
            red: CGFloat(pixel[0]) / 255 * shade,
            green: CGFloat(pixel[1]) / 255 * shade,
            blue: CGFloat(pixel[2]) / 255 * shade,
            alpha: 1
        )
    }

    static func run(snapshot: WindowSnapshot, mainDisplayHeight: CGFloat, duration: Double) -> NSPanel {
        let screen = NSScreen.main?.frame ?? .zero
        let windowFrame = Geometry.appKitFrame(
            fromCGWindowBounds: snapshot.windowBounds,
            mainDisplayHeight: mainDisplayHeight
        )

        // Full-screen panel: the fold needs room beyond the window's own bounds.
        let panel = NSPanel(
            contentRect: screen, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSView(frame: CGRect(origin: .zero, size: screen.size))
        host.wantsLayer = true
        panel.contentView = host

        // Root carries the perspective. Children must be CATransformLayers or their
        // 3D is flattened into a single plane.
        let root = CATransformLayer()
        root.frame = CGRect(
            x: windowFrame.minX - screen.minX, y: windowFrame.minY - screen.minY,
            width: windowFrame.width, height: windowFrame.height
        )
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 900
        root.sublayerTransform = perspective
        host.layer?.addSublayer(root)

        let half = windowFrame.width / 2
        let size = CGSize(width: half, height: windowFrame.height)

        // Left half: never moves.
        let left = CALayer()
        left.frame = CGRect(origin: .zero, size: size)
        left.contents = snapshot.image
        left.contentsRect = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        left.contentsGravity = .resize
        root.addSublayer(left)

        // Hinge pivots about the centre crease: anchorPoint on its own left edge.
        let hinge = CATransformLayer()
        hinge.bounds = CGRect(origin: .zero, size: size)
        hinge.anchorPoint = CGPoint(x: 0, y: 0.5)
        hinge.position = CGPoint(x: half, y: windowFrame.height / 2)
        root.addSublayer(hinge)

        // Front shows the right half of the snapshot and vanishes past 90 degrees.
        let front = CALayer()
        front.frame = CGRect(origin: .zero, size: size)
        front.contents = snapshot.image
        front.contentsRect = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        front.contentsGravity = .resize
        front.isDoubleSided = false
        hinge.addSublayer(front)

        // Back is the window's own colour, shaded like the Figma's body facet.
        let back = CALayer()
        back.frame = CGRect(origin: .zero, size: size)
        back.backgroundColor = paperColor(for: snapshot.image, shade: 0.82)
        back.isDoubleSided = false
        back.transform = CATransform3DMakeRotation(.pi, 0, 1, 0)
        hinge.addSublayer(back)

        panel.orderFrontRegardless()

        // Fold the right half over onto the left.
        let fold = CABasicAnimation(keyPath: "transform.rotation.y")
        fold.fromValue = 0
        fold.toValue = -Double.pi
        fold.duration = duration
        fold.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fold.fillMode = .forwards
        fold.isRemovedOnCompletion = false
        hinge.add(fold, forKey: "fold")

        return panel
    }
}
