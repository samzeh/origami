import CoreGraphics

/// Decides whether a key-down is exactly Command-Q. Pure, so the rule can be tested
/// without a window server or an event tap.
public enum HotkeyMatch {

    /// Virtual key code for Q on every keyboard layout (codes are physical, not
    /// letters, so this is the key where Q sits on a US layout).
    public static let qKeyCode = CGKeyCode(12)

    /// Modifiers that change the meaning of Cmd+Q into a different system shortcut:
    /// Cmd+Opt+Q logs out, Ctrl+Cmd+Q locks the screen, Cmd+Shift+Q is app-defined.
    private static let disqualifying: CGEventFlags = [
        .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
    ]

    public static func isQuitShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard keyCode == qKeyCode, flags.contains(.maskCommand) else { return false }
        return flags.intersection(disqualifying).isEmpty
    }
}
