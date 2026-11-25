import CoreGraphics
import Foundation
import Testing

@testable import OrigamiKit

// Shared ordered log, so tests can assert that the overlay goes up BEFORE the app
// is told to quit — the ordering the whole illusion depends on.
private final class Recorder: @unchecked Sendable {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

private struct FakeCapturer: WindowCapturing, @unchecked Sendable {
    let recorder: Recorder
    let failure: (any Error)?

    func capture(_ window: WindowInfo) async throws -> WindowSnapshot {
        recorder.record("capture")
        if let failure { throw failure }
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return WindowSnapshot(
            image: context.makeImage()!,
            windowBounds: window.bounds,
            scale: 2,
            metrics: CaptureMetrics(enumerateWindows: .zero, buildFilter: .zero, captureImage: .zero)
        )
    }
}

private struct FakeTerminator: AppTerminating, @unchecked Sendable {
    let recorder: Recorder
    func terminate(pid: pid_t) -> Bool {
        recorder.record("terminate")
        return true
    }
}

private struct FakeWatcher: ProcessWatching, @unchecked Sendable {
    let recorder: Recorder
    let didTerminate: Bool
    func awaitTermination(pid: pid_t, timeout: Duration) async -> Bool {
        recorder.record("await")
        return didTerminate
    }
}

@MainActor
private final class FakeOverlay: OverlayPresenting {
    let recorder: Recorder
    init(recorder: Recorder) { self.recorder = recorder }
    func show(_ snapshot: WindowSnapshot, mainDisplayHeight: CGFloat) { recorder.record("show") }
    func fadeOut(duration: TimeInterval) { recorder.record("fadeOut") }
    func dismiss() { recorder.record("dismiss") }
}

private struct CaptureFailed: Error {}

private func makeWindow() -> WindowInfo {
    WindowInfo(
        id: 1, ownerPID: 42, layer: 0,
        bounds: CGRect(x: 0, y: 0, width: 400, height: 300), alpha: 1, title: "Doc"
    )
}

@MainActor
private func makeCoordinator(
    recorder: Recorder,
    captureFails: Bool = false,
    processDies: Bool = true
) -> (QuitCoordinator, FakeOverlay) {
    let overlay = FakeOverlay(recorder: recorder)
    let coordinator = QuitCoordinator(
        capturer: FakeCapturer(recorder: recorder, failure: captureFails ? CaptureFailed() : nil),
        terminator: FakeTerminator(recorder: recorder),
        watcher: FakeWatcher(recorder: recorder, didTerminate: processDies),
        overlay: overlay,
        mainDisplayHeight: 1000
    )
    return (coordinator, overlay)
}

@Suite("Quit coordinator", .serialized)
@MainActor
struct QuitCoordinatorTests {

    @Test("covers the window before telling the app to quit")
    func coversWindowBeforeQuitting() async {
        // If terminate ran first the window would vanish before the snapshot was up,
        // and the user would see it disappear.
        let recorder = Recorder()
        let (coordinator, _) = makeCoordinator(recorder: recorder)

        _ = await coordinator.handleQuit(of: makeWindow())

        let show = recorder.events.firstIndex(of: "show")
        let terminate = recorder.events.firstIndex(of: "terminate")
        #expect(show != nil && terminate != nil)
        #expect(show! < terminate!)
    }

    @Test("fades the overlay out once the app has actually died")
    func fadesOutWhenAppDies() async {
        let recorder = Recorder()
        let (coordinator, _) = makeCoordinator(recorder: recorder, processDies: true)

        let outcome = await coordinator.handleQuit(of: makeWindow())

        #expect(outcome == .quit)
        #expect(recorder.events.contains("fadeOut"))
        #expect(recorder.events.contains("dismiss") == false)
    }

    @Test("dismisses the overlay when the app refuses to quit")
    func dismissesWhenAppSurvives() async {
        // A save dialog keeps the app alive. The snapshot must come straight down so
        // the real window and its sheet are visible again.
        let recorder = Recorder()
        let (coordinator, _) = makeCoordinator(recorder: recorder, processDies: false)

        let outcome = await coordinator.handleQuit(of: makeWindow())

        #expect(outcome == .aborted)
        #expect(recorder.events.contains("dismiss"))
        #expect(recorder.events.contains("fadeOut") == false)
    }

    @Test("still quits the app when the capture fails")
    func quitsAnywayWhenCaptureFails() async {
        // Cmd+Q must never become worse than it was: no snapshot, but the app
        // still quits.
        let recorder = Recorder()
        let (coordinator, _) = makeCoordinator(recorder: recorder, captureFails: true)

        let outcome = await coordinator.handleQuit(of: makeWindow())

        #expect(outcome == .quitWithoutAnimation)
        #expect(recorder.events.contains("terminate"))
        #expect(recorder.events.contains("show") == false)
    }

    @Test("ignores a second quit while one is already in flight")
    func ignoresReentrantQuit() async {
        let recorder = Recorder()
        let (coordinator, _) = makeCoordinator(recorder: recorder)

        async let first = coordinator.handleQuit(of: makeWindow())
        async let second = coordinator.handleQuit(of: makeWindow())
        let outcomes = await [first, second]

        #expect(outcomes.contains(.ignored))
        #expect(recorder.events.filter { $0 == "terminate" }.count == 1)
    }
}
