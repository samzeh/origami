import CoreGraphics
import Testing

@testable import OrigamiKit

// Builds the dictionary `CGWindowListCopyWindowInfo` returns. Keys are literal
// strings on purpose: that wire format is what we depend on.
private func description(
    number: Any? = 42,
    ownerPID: Any? = 501,
    layer: Any? = 0,
    bounds: [String: Any]? = ["X": 10, "Y": 20, "Width": 800, "Height": 600],
    alpha: Any? = 1.0,
    name: Any? = "Document.txt"
) -> [String: Any] {
    var dictionary: [String: Any] = [:]
    if let number { dictionary["kCGWindowNumber"] = number }
    if let ownerPID { dictionary["kCGWindowOwnerPID"] = ownerPID }
    if let layer { dictionary["kCGWindowLayer"] = layer }
    if let bounds { dictionary["kCGWindowBounds"] = bounds as CFDictionary }
    if let alpha { dictionary["kCGWindowAlpha"] = alpha }
    if let name { dictionary["kCGWindowName"] = name }
    return dictionary
}

@Suite("Parsing a Core Graphics window description")
struct WindowInfoParsingTests {

    @Test("reads every field from a complete description")
    func readsCompleteDescription() throws {
        let parsed = try #require(WindowInfo(coreGraphicsDescription: description()))

        #expect(parsed.id == 42)
        #expect(parsed.ownerPID == 501)
        #expect(parsed.layer == 0)
        #expect(parsed.alpha == 1.0)
        #expect(parsed.title == "Document.txt")
    }

    @Test("maps bounds without transposing the axes or the dimensions")
    func mapsBoundsFaithfully() throws {
        // Deliberately four distinct numbers: a transposition bug survives a
        // square window but not this one.
        let parsed = try #require(
            WindowInfo(
                coreGraphicsDescription: description(
                    bounds: ["X": 11, "Y": 22, "Width": 333, "Height": 444]
                )
            )
        )

        #expect(parsed.bounds == CGRect(x: 11, y: 22, width: 333, height: 444))
    }

    @Test("rejects a description with no window number")
    func rejectsDescriptionWithoutNumber() {
        #expect(WindowInfo(coreGraphicsDescription: description(number: nil)) == nil)
    }

    @Test("rejects a description with no owning process")
    func rejectsDescriptionWithoutOwner() {
        #expect(WindowInfo(coreGraphicsDescription: description(ownerPID: nil)) == nil)
    }

    @Test("rejects a description with no bounds")
    func rejectsDescriptionWithoutBounds() {
        #expect(WindowInfo(coreGraphicsDescription: description(bounds: nil)) == nil)
    }

    @Test("rejects a description whose bounds are not a usable dictionary")
    func rejectsUnusableBounds() {
        #expect(
            WindowInfo(coreGraphicsDescription: description(bounds: ["nonsense": 1])) == nil
        )
    }

    @Test("treats a window with no alpha key as fully opaque")
    func defaultsMissingAlphaToOpaque() throws {
        // A missing alpha should not cause us to discard an otherwise real window.
        let parsed = try #require(WindowInfo(coreGraphicsDescription: description(alpha: nil)))

        #expect(parsed.alpha == 1)
    }

    @Test("treats a window with no layer key as being on the normal layer")
    func defaultsMissingLayerToNormal() throws {
        let parsed = try #require(WindowInfo(coreGraphicsDescription: description(layer: nil)))

        #expect(parsed.layer == 0)
    }

    @Test("leaves the title empty when the name key is absent")
    func leavesTitleEmptyWithoutName() throws {
        // kCGWindowName is absent until Screen Recording permission is granted, so
        // this is the normal case on first launch, not an error.
        let parsed = try #require(WindowInfo(coreGraphicsDescription: description(name: nil)))

        #expect(parsed.title == nil)
    }
}
