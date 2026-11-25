import ApplicationServices
import CoreGraphics
import Foundation

/// Intercepts Cmd+Q system-wide with a `CGEventTap`.
///
/// An event tap is a callback spliced into the window server's keystroke stream;
/// returning nil from it deletes the event. Two constraints shape everything here:
/// it needs Accessibility permission, and a slow callback gets the tap evicted.
public final class HotkeyTap {

    public enum TapError: Error, Equatable {
        /// Accessibility permission has not been granted, so no tap is possible.
        case accessibilityNotTrusted
        /// The window server refused to create the tap.
        case creationFailed
    }

    /// Decides, synchronously and cheaply, whether this Cmd+Q should be intercepted.
    /// Returning nil passes the keystroke through untouched.
    public typealias Decision = @MainActor @Sendable () -> WindowInfo?

    /// Called on the main actor once a Cmd+Q has been swallowed.
    public typealias Handler = @MainActor @Sendable (WindowInfo) -> Void

    private let decide: Decision
    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public var isRunning: Bool { tap != nil }

    public init(decide: @escaping Decision, handler: @escaping Handler) {
        self.decide = decide
        self.handler = handler
    }

    /// Whether Accessibility is granted. Without it the tap cannot be created.
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt pointing the user at the Accessibility settings. The
    /// key is spelled literally because the SDK constant is a non-Sendable global.
    public static func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func start() throws {
        guard Self.isTrusted else { throw TapError.accessibilityNotTrusted }
        guard tap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        // `.defaultTap` is an active tap: it may modify or delete events. A listen-
        // only tap could watch Cmd+Q but never swallow it.
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { throw TapError.creationFailed }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Runs on the main run loop, since that is where the source was added.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        // The system disables a tap whose callback was too slow, or after certain
        // user input. Re-enable rather than silently going deaf.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        guard type == .keyDown else { return passThrough }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard HotkeyMatch.isQuitShortcut(keyCode: keyCode, flags: event.flags) else {
            return passThrough
        }

        // Only a Bool crosses the isolation boundary; CGEvent is not Sendable, and
        // the closures are captured as locals so `self` does not cross either.
        let decide = self.decide
        let handler = self.handler
        let swallow = MainActor.assumeIsolated { () -> Bool in
            // No window worth folding, or an excluded app: let Cmd+Q through so the
            // keystroke behaves exactly as it always did.
            guard let window = decide() else { return false }
            handler(window)
            return true
        }
        return swallow ? nil : passThrough
    }
}
