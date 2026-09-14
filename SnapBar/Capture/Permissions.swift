import AppKit
import CoreGraphics

@MainActor
enum Permissions {
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func showBlankCaptureAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "The screenshot came out empty")
        alert.informativeText = String(localized: "SnapBar needs Screen Recording permission. Open System Settings, turn on SnapBar under Screen Recording, then capture again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
