import AppKit
import CoreGraphics
import QuartzCore

/// A panel that refuses focus and refuses to move, so the swap doesn't shift focus
/// or let the window be dragged.
private final class NonFocusingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws a captured window image into its own bounds with Core Graphics. Kept in a
/// non-flipped view, the system `CGContext.draw(_:in:)` renders images right-side-up.
private final class SnapshotView: NSView {
    var cgImage: CGImage?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let cgImage else { return }
        context.draw(cgImage, in: bounds)
    }
}

/// Lays a captured window back over the screen, in the same place, at the same
/// size, so that replacing the real window with its picture is invisible.
@MainActor
public final class SnapshotOverlay {

    public let panel: NSPanel
    private let snapshotView: SnapshotView
    /// A faint wash used only for debugging
    public let tintView: NSView

    /// The size, in points, at which the snapshot is currently drawn.
    public var snapshotSize: CGSize { snapshotView.frame.size }

    public var isVisible: Bool { panel.isVisible }

    /// Wash the snapshot red when shown, so the swap is visible while developing.
    public var debugTint = false

    private var fadeTimer: Timer?

    public init() {
        panel = NonFocusingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Transparent and borderless, so the captured window's rounded corners stay
        // rounded instead of being filled in and squared off.
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // The capture has no shadow, so AppKit draws one; the panel's exact size and
        // shape make the system shadow match the window's without hand-tuning.
        panel.hasShadow = true

        // Above all ordinary app windows. `.popUpMenu` sits over app content and is
        // composited the normal, scaled way (unlike `.screenSaver`).
        panel.level = .popUpMenu

        // Present on whichever Space the window was on, and alongside full-screen
        // apps rather than being banished to its own desktop.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // Receive mouse events and do nothing with them. Click-through would hand a
        // drag to the real titlebar still sitting underneath during the hand-off.
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false

        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // The snapshot, drawn into its own bounds with Core Graphics.
        snapshotView = SnapshotView(frame: .zero)

        // Debug wash, layered over the snapshot.
        tintView = NSView(frame: .zero)
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = CGColor(red: 1, green: 0, blue: 0, alpha: 0.18)
        tintView.isHidden = true

        let hostView = NSView(frame: .zero)
        hostView.addSubview(snapshotView)
        hostView.addSubview(tintView)
        panel.contentView = hostView
    }

    /// Positions the panel over the window and shows it immediately.
    /// `mainDisplayHeight` is injected (not read from AppKit) so placement is testable.
    public func show(
        _ snapshot: WindowSnapshot,
        mainDisplayHeight: CGFloat,
        tinted: Bool = false
    ) {
        // Placed from the window's own bounds (Core Graphics coordinates), flipped
        // into AppKit's bottom-left space.
        let frame = Geometry.appKitFrame(
            fromCGWindowBounds: snapshot.windowBounds,
            mainDisplayHeight: mainDisplayHeight
        )
        let bounds = CGRect(origin: .zero, size: frame.size)

        panel.alphaValue = 1
        panel.setFrame(frame, display: false)
        panel.contentView?.frame = bounds
        snapshotView.frame = bounds
        tintView.frame = bounds

        snapshotView.cgImage = snapshot.image
        snapshotView.needsDisplay = true

        tintView.isHidden = !tinted

        // Show without activating Origami Close, which would move focus.
        panel.orderFrontRegardless()

        // Recompute the shadow against the snapshot's alpha, so it follows the
        // window's rounded corners rather than a bare rectangle.
        panel.invalidateShadow()
    }

    /// Fades the overlay out — a placeholder ending until the fold exists. Uses a
    /// run-loop timer because an accessory app's window animator never fires.
    public func fadeOut(duration: TimeInterval, completion: @escaping @Sendable () -> Void) {
        fadeTimer?.invalidate()

        let start = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                let progress = min(1, Date().timeIntervalSince(start) / duration)
                self.panel.alphaValue = 1 - progress

                guard progress >= 1 else { return }
                self.fadeTimer?.invalidate()
                self.fadeTimer = nil
                self.dismiss()
                completion()
            }
        }
    }

    public func dismiss() {
        panel.orderOut(nil)
        panel.alphaValue = 1
    }
}

extension SnapshotOverlay: OverlayPresenting {
    public func show(_ snapshot: WindowSnapshot, mainDisplayHeight: CGFloat) {
        show(snapshot, mainDisplayHeight: mainDisplayHeight, tinted: debugTint)
    }

    public func fadeOut(duration: TimeInterval) {
        fadeOut(duration: duration) {}
    }
}
