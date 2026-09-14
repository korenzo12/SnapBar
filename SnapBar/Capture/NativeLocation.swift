import Foundation

/// Points macOS ⌘⇧4 screenshots at a folder, or back to the default. Only runs when the user flips the switch.
enum NativeLocation {
    /// A debug run points at a throwaway domain, so tests never move the real ⇧⌘4 folder.
    static var defaultDomain: String {
        AppEnvironment.home == nil ? "com.apple.screencapture" : "co.il.ckdigital360.snapbar.test-screencapture"
    }

    @discardableResult
    static func apply(folder: URL?, domain: String = NativeLocation.defaultDomain, restartUI: Bool = AppEnvironment.home == nil) -> Bool {
        let args: [String]
        if let folder {
            args = ["write", domain, "location", folder.path]
        } else {
            args = ["delete", domain, "location"]
        }
        let ok = run("/usr/bin/defaults", args)
        if restartUI { _ = run("/usr/bin/killall", ["SystemUIServer"]) }
        Log.info("native location \(folder == nil ? "reset" : "set") domain=\(domain) ok=\(ok)")
        return ok
    }

    static func current(domain: String = NativeLocation.defaultDomain) -> String? {
        UserDefaults(suiteName: domain)?.string(forKey: "location")
    }

    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
