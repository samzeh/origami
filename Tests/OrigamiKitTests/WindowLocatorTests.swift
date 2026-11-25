import CoreGraphics
import Testing

@testable import OrigamiKit

/// Stands in for Core Graphics' window list so the filtering rules can be tested
/// without a real window server.
private struct FakeWindowListing: WindowListing {
    var windows: [WindowInfo] = []
    var failure: (any Error)? = nil

    func onScreenWindows() throws -> [WindowInfo] {
        if let failure { throw failure }
        return windows
    }
}

private struct ListingFailed: Error {}

/// A plausible normal window, overridable per test.
private func window(
    id: CGWindowID = 1,
    pid: pid_t = 100,
    layer: Int = 0,
    bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600),
    alpha: CGFloat = 1,
    title: String? = "Untitled"
) -> WindowInfo {
    WindowInfo(id: id, ownerPID: pid, layer: layer, bounds: bounds, alpha: alpha, title: title)
}

@Suite("Locating an app's frontmost window")
struct WindowLocatorTests {

    @Test("finds nothing when the window list is empty")
    func findsNothingWhenListEmpty() throws {
        let locator = WindowLocator(listing: FakeWindowListing(windows: []))

        #expect(try locator.frontmostWindow(ofPID: 100) == nil)
    }

    @Test("finds nothing when the app owns none of the listed windows")
    func findsNothingWhenAppOwnsNoWindows() throws {
        let listing = FakeWindowListing(windows: [window(id: 1, pid: 999)])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100) == nil)
    }

    @Test("returns the app's window, ignoring other apps' windows in front of it")
    func ignoresOtherAppsWindows() throws {
        // Core Graphics orders the list front to back, so another app's window
        // appears first here.
        let listing = FakeWindowListing(windows: [
            window(id: 1, pid: 999),
            window(id: 2, pid: 100),
        ])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100)?.id == 2)
    }

    @Test("returns the frontmost of several windows belonging to the app")
    func returnsFrontmostOfSeveral() throws {
        let listing = FakeWindowListing(windows: [
            window(id: 7, pid: 100),
            window(id: 8, pid: 100),
            window(id: 9, pid: 100),
        ])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100)?.id == 7)
    }

    @Test("skips menus and tooltips sitting above the normal window layer")
    func skipsWindowsAboveNormalLayer() throws {
        // A pulled-down menu or a tooltip belongs to the app and sits in front,
        // but it is not the window the user thinks they are closing.
        let listing = FakeWindowListing(windows: [
            window(id: 1, pid: 100, layer: 25),
            window(id: 2, pid: 100, layer: 0),
        ])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100)?.id == 2)
    }

    @Test("skips fully transparent windows")
    func skipsTransparentWindows() throws {
        let listing = FakeWindowListing(windows: [
            window(id: 1, pid: 100, alpha: 0),
            window(id: 2, pid: 100, alpha: 1),
        ])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100)?.id == 2)
    }

    @Test("skips the tiny offscreen helper windows many apps keep around")
    func skipsTinyHelperWindows() throws {
        let listing = FakeWindowListing(windows: [
            window(id: 1, pid: 100, bounds: CGRect(x: 0, y: 0, width: 1, height: 1)),
            window(id: 2, pid: 100, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100)?.id == 2)
    }

    @Test("accepts a window exactly at the minimum size")
    func acceptsWindowAtMinimumSize() throws {
        let minimum = WindowLocator.minimumWindowSize
        let listing = FakeWindowListing(windows: [
            window(id: 1, pid: 100, bounds: CGRect(origin: .zero, size: minimum))
        ])
        let locator = WindowLocator(listing: listing)

        #expect(try locator.frontmostWindow(ofPID: 100)?.id == 1)
    }

    @Test("propagates a failure from the underlying window list")
    func propagatesListingFailure() {
        let listing = FakeWindowListing(failure: ListingFailed())
        let locator = WindowLocator(listing: listing)

        #expect(throws: ListingFailed.self) {
            try locator.frontmostWindow(ofPID: 100)
        }
    }
}
