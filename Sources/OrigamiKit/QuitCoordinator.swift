import AppKit
import CoreGraphics
import Foundation

/// Asks an application to quit, the same way Cmd+Q does.
public protocol AppTerminating: Sendable {
    func terminate(pid: pid_t) -> Bool
}

/// Waits for a process to actually exit. Returns false if it is still alive when
/// the timeout expires, which is how a save dialog shows up.
public protocol ProcessWatching: Sendable {
    func awaitTermination(pid: pid_t, timeout: Duration) async -> Bool
}

/// What the coordinator needs from the overlay, so the state machine can be tested
/// without a window server.
@MainActor
public protocol OverlayPresenting: AnyObject {
    func show(_ snapshot: WindowSnapshot, mainDisplayHeight: CGFloat)
    func fadeOut(duration: TimeInterval)
    func dismiss()
}

/// Runs the swap: cover the window, ask the app to quit, then animate only once the
/// app has really gone. Every failure path still quits the app.
@MainActor
public final class QuitCoordinator {

    public enum Outcome: Equatable, Sendable {
        /// App died; the snapshot animated away.
        case quit
        /// App is still running (a save dialog, most likely); snapshot removed.
        case aborted
        /// Capture failed, so the app was quit with no snapshot at all.
        case quitWithoutAnimation
        /// A quit was already in flight.
        case ignored
    }

    /// How long to wait for the app to exit before assuming it put up a dialog.
    public static let terminationTimeout = Duration.milliseconds(1500)
    public static let fadeDuration: TimeInterval = 0.35

    private let capturer: any WindowCapturing
    private let terminator: any AppTerminating
    private let watcher: any ProcessWatching
    private let overlay: any OverlayPresenting
    private var isRunning = false

    /// Re-read before each quit, so attaching or rearranging displays is picked up.
    public var mainDisplayHeight: CGFloat

    public init(
        capturer: any WindowCapturing,
        terminator: any AppTerminating,
        watcher: any ProcessWatching,
        overlay: any OverlayPresenting,
        mainDisplayHeight: CGFloat
    ) {
        self.capturer = capturer
        self.terminator = terminator
        self.watcher = watcher
        self.overlay = overlay
        self.mainDisplayHeight = mainDisplayHeight
    }

    public func handleQuit(of window: WindowInfo) async -> Outcome {
        guard !isRunning else { return .ignored }
        isRunning = true
        defer { isRunning = false }

        // Capture first. If this fails there is no snapshot to show, but the user
        // still pressed Cmd+Q, so the app must quit regardless.
        let snapshot: WindowSnapshot
        do {
            snapshot = try await capturer.capture(window)
        } catch {
            _ = terminator.terminate(pid: window.ownerPID)
            return .quitWithoutAnimation
        }

        // Cover the window before it can disappear, then ask the app to quit.
        overlay.show(snapshot, mainDisplayHeight: mainDisplayHeight)
        _ = terminator.terminate(pid: window.ownerPID)

        let died = await watcher.awaitTermination(
            pid: window.ownerPID,
            timeout: Self.terminationTimeout
        )

        guard died else {
            // Still alive: a save dialog. Take the snapshot straight down so the
            // real window and its sheet are visible again.
            overlay.dismiss()
            return .aborted
        }

        overlay.fadeOut(duration: Self.fadeDuration)
        return .quit
    }
}

/// Terminates via `NSRunningApplication`, which posts the same quit Apple event
/// Cmd+Q does, so apps get their normal save prompts.
public struct RunningApplicationTerminator: AppTerminating {
    public init() {}

    public func terminate(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.terminate()
    }
}

/// Waits on the workspace's terminate notification rather than polling, with a
/// timeout as the signal that the app put up a dialog instead of quitting.
public struct WorkspaceProcessWatcher: ProcessWatching {
    public init() {}

    public func awaitTermination(pid: pid_t, timeout: Duration) async -> Bool {
        if NSRunningApplication(processIdentifier: pid) == nil { return true }

        let deadline = ContinuousClock().now.advanced(by: timeout)
        while ContinuousClock().now < deadline {
            if let app = NSRunningApplication(processIdentifier: pid) {
                if app.isTerminated { return true }
            } else {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }
}
