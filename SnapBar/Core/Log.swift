import Foundation
import os

/// Append-only log at ~/Library/Logs/SnapBar/snapbar.log. Ledger proofs quote this file.
final class Log: @unchecked Sendable {
    static let shared = Log()

    let fileURL: URL
    private let queue = DispatchQueue(label: "co.il.ckdigital360.snapbar.log")
    private let logger = Logger(subsystem: "co.il.ckdigital360.snapbar", category: "app")
    private let formatter: DateFormatter

    private init() {
        let dir = AppEnvironment.home?.appendingPathComponent("Logs", isDirectory: true)
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SnapBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("snapbar.log")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter = f
    }

    static func info(_ message: String) { shared.write(message) }

    /// Whole milliseconds elapsed since `start`, for measurement lines.
    static func ms(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private func write(_ message: String) {
        let line = formatter.string(from: Date()) + " " + message + "\n"
        logger.info("\(message, privacy: .public)")
        let url = fileURL
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
