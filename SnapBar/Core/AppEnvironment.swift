import Foundation

/// Debug builds can run inside a test folder (SNAPBAR_HOME) so verification never touches the real
/// library, settings, Desktop or macOS screenshot preferences. Release builds ignore both variables.
enum AppEnvironment {
    static let home: URL? = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["SNAPBAR_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }()

    /// Debug-only stand-in for /usr/sbin/screencapture, to exercise everything around a capture
    /// (naming, cancel, flags, clipboard timing) when the test session may not record the screen.
    static let captureTool: String? = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["SNAPBAR_CAPTURE_TOOL"], !path.isEmpty { return path }
        #endif
        return nil
    }()

    static let nativeFolderOverride: URL? = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["SNAPBAR_NATIVE_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return nil
    }()
}
