import AppKit
import OrigamiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Apps whose Cmd+Q we never touch. Finder's Cmd+Q does not quit it anyway, and
    /// intercepting our own would make the app impossible to quit.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.loginwindow",
    ]

    private let overlay = SnapshotOverlay()
    private let locator = WindowLocator(listing: CoreGraphicsWindowListing())
    private var statusItem: NSStatusItem?
    private var tap: HotkeyTap?
    private var coordinator: QuitCoordinator?
    private var isEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // On while the fold does not exist yet, so the swap is visible. Turn it off
        // from the menu once you trust it.
        overlay.debugTint = true

        coordinator = QuitCoordinator(
            capturer: ScreenCaptureKitCapturer(),
            terminator: RunningApplicationTerminator(),
            watcher: WorkspaceProcessWatcher(),
            overlay: overlay,
            mainDisplayHeight: SystemScreens.mainDisplayHeight()
        )
        setUpMenuBar()
        requestScreenRecordingIfNeeded()
        startTap()
    }

    /// Capture needs Screen Recording, which is a different grant from Accessibility.
    /// Without it the snapshot fails and the app just quits with no animation.
    private func requestScreenRecordingIfNeeded() {
        let granted = CGPreflightScreenCaptureAccess()
        log("screen recording granted: \(granted)")
        guard !granted else { return }
        log("requesting screen recording; a restart is needed after granting it")
        CGRequestScreenCaptureAccess()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap?.stop()
    }

    // MARK: - Menu bar

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "paperplane", accessibilityDescription: "Origami Close"
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Fold windows on ⌘Q", action: #selector(toggleEnabled), keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = isEnabled ? .on : .off
        menu.addItem(toggle)

        let tint = NSMenuItem(
            title: "Tint snapshot red (debug)", action: #selector(toggleTint), keyEquivalent: ""
        )
        tint.target = self
        tint.state = overlay.debugTint ? .on : .off
        menu.addItem(tint)

        menu.addItem(.separator())

        if !HotkeyTap.isTrusted {
            let grant = NSMenuItem(
                title: "Grant Accessibility access…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Origami Close", action: #selector(quit), keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func statusLine() -> String {
        if !HotkeyTap.isTrusted { return "Needs Accessibility access" }
        if !CGPreflightScreenCaptureAccess() { return "Needs Screen Recording access" }
        return tap?.isRunning == true ? "Watching for ⌘Q" : "Not watching"
    }

    private func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleTint() {
        overlay.debugTint.toggle()
        refreshMenu()
    }

    @objc private func openAccessibilitySettings() {
        HotkeyTap.promptForTrust()
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        if let url { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - The tap

    /// Appends to a file, which is readable regardless of how the app was launched.
    /// Unified logging does not reliably capture a Finder-launched accessory app.
    private func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("origami.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func startTap() {
        log("accessibility trusted: \(HotkeyTap.isTrusted)")
        let tap = HotkeyTap(
            decide: { [weak self] in self?.windowToFold() },
            handler: { [weak self] window in self?.beginQuit(of: window) }
        )
        do {
            try tap.start()
            self.tap = tap
            log("event tap started; watching for Cmd+Q")
        } catch {
            // Without the tap we simply never intercept; Cmd+Q behaves normally.
            log("event tap unavailable: \(error)")
        }
        refreshMenu()
    }

    /// The cheap synchronous check that runs inside the tap callback. Returning nil
    /// lets the keystroke through untouched.
    private func windowToFold() -> WindowInfo? {
        log("saw Cmd+Q")
        guard isEnabled else {
            log("  passing through: folding is switched off")
            return nil
        }
        guard let app = FrontmostApplication.current() else {
            log("  passing through: no frontmost application")
            return nil
        }
        guard !isExcluded(app) else {
            log("  passing through: \(app.name) is excluded")
            return nil
        }
        do {
            guard let window = try locator.frontmostWindow(ofPID: app.pid) else {
                log("  passing through: \(app.name) has no normal window on this Space")
                return nil
            }
            log("  intercepting \(app.name), window \(window.id) \(window.bounds)")
            return window
        } catch {
            log("  passing through: window lookup failed (\(error))")
            return nil
        }
    }

    private func isExcluded(_ app: FrontmostApplication.Identity) -> Bool {
        if app.pid == ProcessInfo.processInfo.processIdentifier { return true }
        guard let bundleID = app.bundleIdentifier else { return false }
        return Self.excludedBundleIDs.contains(bundleID)
    }

    private func beginQuit(of window: WindowInfo) {
        log("intercepted Cmd+Q for pid \(window.ownerPID), window \(window.id)")
        guard let coordinator else { return }
        coordinator.mainDisplayHeight = SystemScreens.mainDisplayHeight()
        Task {
            let outcome = await coordinator.handleQuit(of: window)
            log("  outcome: \(outcome)")
        }
    }
}
