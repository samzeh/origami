import AppKit
import CoreGraphics
import Foundation
import ImageIO
import OrigamiKit
import UniformTypeIdentifiers

// Terminal harness for the capture + overlay layer. Modes: [countdown] [repeats],
// --app <name>, --window <id>, --list. Flags: --overlay [s], --tint, --reveal.

// MARK: - Formatting

func f(_ value: CGFloat) -> String { String(format: "%.1f", value) }

func short(_ rect: CGRect) -> String {
    "(\(f(rect.origin.x)), \(f(rect.origin.y)))  \(f(rect.width)) x \(f(rect.height))"
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
    var ms: String { String(format: "%7.2fms", milliseconds) }
}

func summarise(_ samples: [Double]) -> String {
    let sorted = samples.sorted()
    return "min \(String(format: "%.2f", sorted.first ?? 0))ms  "
        + "median \(String(format: "%.2f", sorted[sorted.count / 2]))ms  "
        + "max \(String(format: "%.2f", sorted.last ?? 0))ms"
}

func writePNG(_ image: CGImage, to url: URL) throws {
    struct EncodingFailed: Error {}
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        )
    else { throw EncodingFailed() }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw EncodingFailed() }
}

// MARK: - Arguments

enum Mode {
    case frontmost(countdown: Int, repeats: Int)
    case list
    case window(id: CGWindowID, repeats: Int)
    case app(name: String, repeats: Int)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let reveal = arguments.contains("--reveal")
arguments.removeAll { $0 == "--reveal" }

let tinted = arguments.contains("--tint")
arguments.removeAll { $0 == "--tint" }

// --overlay [seconds]: after capturing, lay the snapshot back over the screen.
var overlayHold: Double? = nil
if let index = arguments.firstIndex(of: "--overlay") {
    arguments.remove(at: index)
    if index < arguments.count, let seconds = Double(arguments[index]) {
        overlayHold = seconds
        arguments.remove(at: index)
    } else {
        overlayHold = 6
    }
}

// An accessory app: no Dock icon. The real app does the same via LSUIElement.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let mode: Mode = {
    if arguments.first == "--list" { return .list }
    if arguments.first == "--app", arguments.count > 1 {
        return .app(name: arguments[1], repeats: Int(arguments.count > 2 ? arguments[2] : "") ?? 5)
    }
    if arguments.first == "--window", arguments.count > 1, let id = UInt32(arguments[1]) {
        return .window(id: id, repeats: Int(arguments.count > 2 ? arguments[2] : "") ?? 5)
    }
    return .frontmost(
        countdown: Int(arguments.count > 0 ? arguments[0] : "") ?? 3,
        repeats: Int(arguments.count > 1 ? arguments[1] : "") ?? 5
    )
}()

// MARK: - Permission

// Screen Recording is the only permission the capture layer needs. Run from a
// terminal, macOS attributes the grant to the terminal app rather than this binary.
if !CGPreflightScreenCaptureAccess() {
    print("Screen Recording permission not granted. Requesting it now...")
    let granted = CGRequestScreenCaptureAccess()
    print(granted ? "Granted." : "Denied. Grant it in System Settings and re-run.")
    if !granted { exit(1) }
}

let clock = ContinuousClock()
let listing = CoreGraphicsWindowListing()
let locator = WindowLocator(listing: listing)
let screens = SystemScreens.current()
let mainHeight = SystemScreens.mainDisplayHeight()

// MARK: - List mode

if case .list = mode {
    let runningApps = NSWorkspace.shared.runningApplications
    func name(for pid: pid_t) -> String {
        runningApps.first { $0.processIdentifier == pid }?.localizedName ?? "pid \(pid)"
    }

    print("")
    print("CANDIDATE WINDOWS  (normal layer, visible, at least \(f(WindowLocator.minimumWindowSize.width))pt)")
    print("     id  size              app")
    for window in try listing.onScreenWindows()
    where window.layer == 0 && window.alpha > 0
        && window.bounds.width >= WindowLocator.minimumWindowSize.width
        && window.bounds.height >= WindowLocator.minimumWindowSize.height
    {
        let size = String(format: "%7.0f x %-7.0f", window.bounds.width, window.bounds.height)
        print("  \(String(format: "%5d", window.id))  \(size)  \(name(for: window.ownerPID))")
    }
    exit(0)
}

// MARK: - Locate

// The lookup an event tap callback would run synchronously. Measured repeatedly
// because the first call pays one-off setup the real hot path would not.
var lookupSamples: [Double] = []
var target: WindowInfo?
var appName = "—"
var appBundle: String? = nil
var targetPID: pid_t = 0

switch mode {
case .frontmost(let countdown, _):
    if countdown > 0 {
        print("Bring the window you want to capture to the front.")
        for remaining in stride(from: countdown, through: 1, by: -1) {
            print("  \(remaining)...")
            try await Task.sleep(for: .seconds(1))
        }
    }
    for _ in 1...20 {
        var found: WindowInfo?
        let elapsed = try clock.measure {
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            found = try locator.frontmostWindow(ofPID: app.processIdentifier)
        }
        lookupSamples.append(elapsed.milliseconds)
        target = found
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
        print("No frontmost application."); exit(1)
    }
    appName = app.localizedName ?? "(unnamed)"
    appBundle = app.bundleIdentifier
    targetPID = app.processIdentifier

case .window(let id, _):
    guard let found = try listing.onScreenWindows().first(where: { $0.id == id }) else {
        print("No visible window with id \(id). Try --list."); exit(1)
    }
    target = found
    targetPID = found.ownerPID
    let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == found.ownerPID }
    appName = app?.localizedName ?? "pid \(found.ownerPID)"
    appBundle = app?.bundleIdentifier

case .app(let name, _):
    // Regular (Dock-bearing) apps only, so "Code" cannot match a background agent.
    let candidates = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular
            && ($0.localizedName ?? "").localizedCaseInsensitiveContains(name)
    }
    guard let app = candidates.first else {
        print("No running app whose name contains \"\(name)\". Running apps:")
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            print("  \(running.localizedName ?? "—")")
        }
        exit(1)
    }
    appName = app.localizedName ?? "(unnamed)"
    appBundle = app.bundleIdentifier
    targetPID = app.processIdentifier
    target = try locator.frontmostWindow(ofPID: targetPID)
    if target == nil {
        print("\(appName) is running but has no capturable window on this Space.")
        print("Core Graphics lists only the current Space's windows — switch to the")
        print("desktop holding it (not full screen) and re-run.")
        exit(1)
    }

case .list:
    break
}

guard let target else {
    print("\(appName) (pid \(targetPID)) has no normal window to capture.")
    exit(1)
}

let appKitFrame = Geometry.appKitFrame(fromCGWindowBounds: target.bounds, mainDisplayHeight: mainHeight)
let scale = Geometry.backingScale(for: appKitFrame, screens: screens)
let aspect = target.bounds.width / target.bounds.height

print("")
print("TARGET")
print("  app               \(appName)  (pid \(targetPID))")
print("  bundle            \(appBundle ?? "—")")
print("  window id         \(target.id)")
print("  title             \(target.title ?? "— (needs Screen Recording)")")
print("  CG bounds         \(short(target.bounds))   (origin top-left)")
print("  AppKit frame      \(short(appKitFrame))   (origin bottom-left)")
print("  backing scale     \(scale)x")
print("  aspect ratio      \(String(format: "%.2f", aspect))")
print("  shape by PRD      \(aspect > 1.3 ? "airplane" : "crane")")

if !lookupSamples.isEmpty {
    print("")
    print("SYNCHRONOUS LOOKUP  (what an event tap callback would cost)")
    print("  \(summarise(lookupSamples))")
}

// MARK: - Capture

let repeats: Int = {
    switch mode {
    case .frontmost(_, let r), .window(_, let r), .app(_, let r): return max(1, r)
    case .list: return 1
    }
}()

let capturer = ScreenCaptureKitCapturer()
var snapshots: [WindowSnapshot] = []

print("")
print("CAPTURE  (\(repeats) runs; the first is the cold one that matters)")
print("  run    enumerate       filter      capture        total")
for run in 1...repeats {
    do {
        let snapshot = try await capturer.capture(target)
        let m = snapshot.metrics
        print("  \(String(format: "%3d", run))  \(m.enumerateWindows.ms)  \(m.buildFilter.ms)  "
            + "\(m.captureImage.ms)  \(m.total.ms)")
        snapshots.append(snapshot)
    } catch {
        print("  \(String(format: "%3d", run))  failed: \(error)")
    }
}

guard let snapshot = snapshots.last else {
    print("\nEvery capture failed."); exit(1)
}

print("")
print("  cold              \(String(format: "%.2f", snapshots[0].metrics.total.milliseconds))ms")
if snapshots.count > 1 {
    print("  warm              \(summarise(snapshots.dropFirst().map(\.metrics.total.milliseconds)))")
}
print("  image pixels      \(snapshot.pixelSize.width) x \(snapshot.pixelSize.height)  @\(snapshot.scale)x")

// MARK: - Save

let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("captures")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let stamp = ISO8601DateFormatter()
stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
let safeName = appName.replacingOccurrences(of: " ", with: "-")
let file = directory.appendingPathComponent(
    "\(safeName)-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "")).png"
)
try writePNG(snapshot.image, to: file)
print("  saved             \(file.path)")

if reveal {
    NSWorkspace.shared.open(file)
}

// MARK: - Overlay

guard let hold = overlayHold else {
    if !reveal {
        print("")
        print("  Pass --overlay to lay the snapshot back over the window, or --reveal")
        print("  to open the PNG in Preview.")
    }
    exit(0)
}

let overlay = await MainActor.run { () -> SnapshotOverlay in
    let overlay = SnapshotOverlay()
    overlay.show(snapshot, mainDisplayHeight: mainHeight, tinted: tinted)
    return overlay
}

print("")
print("OVERLAY IS UP  (\(String(format: "%.0f", hold))s)")
print("  What you are looking at over \(appName) is a picture of it.")
if tinted {
    print("  The red wash confirms you are seeing the snapshot, not the window.")
}
print("  Try to drag the window — nothing moves; the panel swallows the mouse.")

// A run-loop timer rather than a bare sleep: the panel needs the run loop serviced
// to draw at all.
Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { _ in
    MainActor.assumeIsolated {
        overlay.fadeOut(duration: 0.4) {
            print("  faded out        done")
            exit(0)
        }
    }
}
// Belt and braces: this panel is above everything, so never let it hang on screen.
Timer.scheduledTimer(withTimeInterval: hold + 3, repeats: false) { _ in
    print("  watchdog fired — exiting")
    exit(2)
}

application.run()
