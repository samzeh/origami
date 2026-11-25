import AppKit
import CoreGraphics
import Foundation

public enum WindowListingError: Error {
    /// The window server returned something other than a list of descriptions.
    case listUnavailable
}

/// The real window list, from the window server. Needs no Screen Recording grant:
/// geometry is readable without it, only `kCGWindowName` is withheld.
public struct CoreGraphicsWindowListing: WindowListing {

    public init() {}

    public func onScreenWindows() throws -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard
            let descriptions = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else {
            throw WindowListingError.listUnavailable
        }

        return descriptions.compactMap(WindowInfo.init(coreGraphicsDescription:))
    }
}

/// Which app is in front, and therefore which app a Cmd+Q is aimed at.
public enum FrontmostApplication {

    public struct Identity: Equatable, Sendable {
        public let pid: pid_t
        public let name: String
        public let bundleIdentifier: String?

        public init(pid: pid_t, name: String, bundleIdentifier: String?) {
            self.pid = pid
            self.name = name
            self.bundleIdentifier = bundleIdentifier
        }
    }

    public static func current() -> Identity? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Identity(
            pid: app.processIdentifier,
            name: app.localizedName ?? "(unnamed)",
            bundleIdentifier: app.bundleIdentifier
        )
    }
}

/// The displays, as AppKit sees them.
public enum SystemScreens {

    public static func current() -> [ScreenGeometry] {
        NSScreen.screens.map {
            ScreenGeometry(frame: $0.frame, backingScale: $0.backingScaleFactor)
        }
    }

    /// Height used to flip between Core Graphics and AppKit coordinates.
    public static func mainDisplayHeight() -> CGFloat {
        Geometry.flipHeight(screens: current())
    }
}
