import Foundation
import ServiceManagement

/// Opens SnapBar when the user logs in.
///
/// macOS 13 introduced `SMAppService`, but it reports `.notFound` for a build that is only signed
/// locally, which is what anyone gets when they build this project themselves. So the modern service
/// is used when it works, and a plain LaunchAgent is written when it does not.
@MainActor
enum LaunchAtLogin {
    private static var modernServiceAvailable: Bool {
        SMAppService.mainApp.status != .notFound
    }

    static var agentURL: URL {
        let directory = AppEnvironment.home?.appendingPathComponent("LaunchAgents", isDirectory: true)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return directory.appendingPathComponent("co.il.ckdigital360.snapbar.plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func set(_ enabled: Bool) {
        if modernServiceAvailable {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                logStatus()
                return
            } catch {
                Log.info("launchAtLogin service failed enabled=\(enabled) error=\(error.localizedDescription), using a LaunchAgent")
            }
        }
        writeAgent(enabled)
    }

    /// The fallback: a LaunchAgent that starts the app at login. Works without a signing certificate.
    private static func writeAgent(_ enabled: Bool) {
        let url = agentURL
        guard enabled else {
            try? FileManager.default.removeItem(at: url)
            Log.info("launchAtLogin agent removed path=\(url.path)")
            return
        }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SnapBar").path
        let plist: [String: Any] = [
            "Label": "co.il.ckdigital360.snapbar",
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            Log.info("launchAtLogin agent written path=\(url.path) target=\(executable)")
        } catch {
            Log.info("launchAtLogin agent failed error=\(error.localizedDescription)")
        }
    }

    static func logStatus() {
        Log.info("launchAtLogin status=\(describe(SMAppService.mainApp.status)) agent=\(FileManager.default.fileExists(atPath: agentURL.path)) enabled=\(isEnabled)")
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }
}
