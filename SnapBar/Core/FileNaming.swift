import Foundation

enum FileNaming {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]
    /// Name prefixes macOS gives its own screenshots, per system language.
    static let nativePrefixes = ["צילום מסך", "Screenshot", "Screen Shot"]

    static func captureFileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "SnapBar \(f.string(from: date)).png"
    }

    static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isNativeScreenshot(name: String) -> Bool {
        guard isImageFile(URL(fileURLWithPath: name)), !name.hasPrefix("SnapBar ") else { return false }
        let normalized = name.precomposedStringWithCanonicalMapping
        return nativePrefixes.contains { normalized.hasPrefix($0.precomposedStringWithCanonicalMapping) }
    }

    static func uniqueURL(in folder: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    /// Where macOS saves ⌘⇧4 screenshots: `location` in com.apple.screencapture, else the Desktop.
    static func systemScreenshotFolder(domain: String = "com.apple.screencapture") -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let raw = UserDefaults(suiteName: domain)?.string(forKey: "location"), !raw.isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }
}
