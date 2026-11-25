import CoreGraphics
import Testing

@testable import OrigamiKit

@Suite("Recognising Command-Q")
struct HotkeyMatchTests {

    // The tap sees every key-down in the session. Anything that is not exactly
    // Cmd+Q must pass through untouched, or we break unrelated shortcuts.

    private let q = CGKeyCode(12)
    private let w = CGKeyCode(13)

    @Test("matches a plain Command-Q")
    func matchesCommandQ() {
        #expect(HotkeyMatch.isQuitShortcut(keyCode: q, flags: [.maskCommand]))
    }

    @Test("ignores Q without Command")
    func ignoresQAlone() {
        #expect(HotkeyMatch.isQuitShortcut(keyCode: q, flags: []) == false)
    }

    @Test("ignores Command with another key")
    func ignoresCommandW() {
        #expect(HotkeyMatch.isQuitShortcut(keyCode: w, flags: [.maskCommand]) == false)
    }

    @Test("ignores Command-Option-Q, which is a different shortcut")
    func ignoresCommandOptionQ() {
        // Cmd+Opt+Q is log out. Swallowing it would be actively harmful.
        #expect(HotkeyMatch.isQuitShortcut(keyCode: q, flags: [.maskCommand, .maskAlternate]) == false)
    }

    @Test("ignores Command-Shift-Q, which is a different shortcut")
    func ignoresCommandShiftQ() {
        #expect(HotkeyMatch.isQuitShortcut(keyCode: q, flags: [.maskCommand, .maskShift]) == false)
    }

    @Test("ignores Control-Command-Q, which locks the screen")
    func ignoresControlCommandQ() {
        #expect(HotkeyMatch.isQuitShortcut(keyCode: q, flags: [.maskCommand, .maskControl]) == false)
    }

    @Test("tolerates flags the system always sets")
    func toleratesNonModifierFlags() {
        // Caps lock and the numeric-pad bit ride along on ordinary events and must
        // not stop a real Cmd+Q from matching.
        #expect(HotkeyMatch.isQuitShortcut(keyCode: q, flags: [.maskCommand, .maskAlphaShift]))
    }
}
