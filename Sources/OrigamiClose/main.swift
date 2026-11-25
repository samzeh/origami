import AppKit

// An accessory app: menu bar only, no Dock icon. The bundle's Info.plist sets
// LSUIElement too, which is what matters when launched from Finder.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
