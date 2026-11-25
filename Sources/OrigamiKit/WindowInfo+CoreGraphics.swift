import CoreGraphics
import Foundation

extension WindowInfo {

    /// Builds a window from one `CGWindowListCopyWindowInfo` entry. Returns nil only
    /// when a required field is missing; layer, alpha and title default when absent.
    public init?(coreGraphicsDescription description: [String: Any]) {
        guard
            let number = description[kCGWindowNumber as String] as? NSNumber,
            let owner = description[kCGWindowOwnerPID as String] as? NSNumber,
            let boundsDescription = description[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDescription as CFDictionary)
        else { return nil }

        let layer = (description[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (description[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1

        self.init(
            id: number.uint32Value,
            ownerPID: owner.int32Value,
            layer: layer,
            bounds: bounds,
            alpha: CGFloat(alpha),
            title: description[kCGWindowName as String] as? String
        )
    }
}
