import CoreGraphics
import Foundation

/// One on-screen window, as the window server describes it.
public struct WindowInfo: Equatable, Sendable {
    public let id: CGWindowID
    public let ownerPID: pid_t
    /// 0 is the normal window layer. Menus, tooltips and panels sit above it.
    public let layer: Int
    /// Core Graphics coordinates: origin at the top-left of the main display.
    public let bounds: CGRect
    public let alpha: CGFloat
    /// Only populated once Screen Recording permission has been granted.
    public let title: String?

    public init(
        id: CGWindowID,
        ownerPID: pid_t,
        layer: Int,
        bounds: CGRect,
        alpha: CGFloat,
        title: String?
    ) {
        self.id = id
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
        self.title = title
    }
}

/// Source of the on-screen window list. A protocol so the filtering rules can be
/// tested without a window server.
public protocol WindowListing: Sendable {
    /// On-screen windows, ordered front to back.
    func onScreenWindows() throws -> [WindowInfo]
}

/// Picks out the window a user means when they quit an app: the frontmost entry in
/// the window-server list that survives filtering out menus, tooltips and helpers.
public struct WindowLocator {

    /// Windows smaller than this in either dimension are treated as helpers rather
    /// than something the user could be looking at.
    public static let minimumWindowSize = CGSize(width: 40, height: 40)

    private let listing: any WindowListing

    public init(listing: any WindowListing) {
        self.listing = listing
    }

    public func frontmostWindow(ofPID pid: pid_t) throws -> WindowInfo? {
        try listing.onScreenWindows().first { candidate in
            candidate.ownerPID == pid
                && candidate.layer == 0
                && candidate.alpha > 0
                && candidate.bounds.width >= Self.minimumWindowSize.width
                && candidate.bounds.height >= Self.minimumWindowSize.height
        }
    }
}
