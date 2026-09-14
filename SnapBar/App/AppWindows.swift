import AppKit

/// SnapBar lives in the menu bar. While a real window is open it also shows in the Dock and ⌘Tab.
@MainActor
enum AppWindows {
    private static var open = Set<ObjectIdentifier>()

    static func didOpen(_ window: NSWindow?) {
        guard let window else { return }
        open.insert(ObjectIdentifier(window))
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            Log.info("activationPolicy=regular")
        }
        NSApp.activate()
    }

    static func didClose(_ window: NSWindow?) {
        guard let window else { return }
        open.remove(ObjectIdentifier(window))
        if open.isEmpty, NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
            Log.info("activationPolicy=accessory")
        }
    }
}
