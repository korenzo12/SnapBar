import Foundation

enum StableFile {
    /// Polls size every `interval`; succeeds once two reads in a row match and are non-zero.
    static func waitUntilStable(interval: TimeInterval, timeout: TimeInterval, queue: DispatchQueue,
                                size: @escaping @Sendable () -> Int64?,
                                completion: @escaping @Sendable (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        @Sendable func poll(last: Int64?) {
            let current = size()
            if let current, current > 0, current == last {
                completion(true)
                return
            }
            if Date() > deadline {
                completion(false)
                return
            }
            queue.asyncAfter(deadline: .now() + interval) { poll(last: current) }
        }
        poll(last: nil)
    }

    static func size(of url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return nil }
        return n.int64Value
    }
}

/// Watches the folder macOS saves ⌘⇧4 screenshots into and reports each new one once it is fully written.
final class NativeWatcher: @unchecked Sendable {
    let folder: URL
    private let onNew: @MainActor (URL) -> Void
    private let queue = DispatchQueue(label: "co.il.ckdigital360.snapbar.native")
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var pending: Set<String> = []

    init(folder: URL, onNew: @escaping @MainActor (URL) -> Void) {
        self.folder = folder
        self.onNew = onNew
    }

    /// Runs off the main thread: opening a protected folder such as the Desktop blocks until macOS
    /// gets an answer to its folder-access prompt, which would otherwise freeze the rest of launch.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.known = Set(self.screenshotNames())
            let fd = open(self.folder.path, O_EVTONLY)
            guard fd >= 0 else {
                Log.info("native watcher open failed folder=\(self.folder.path) errno=\(errno)")
                return
            }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: self.queue)
            src.setEventHandler { [weak self] in self?.scan() }
            src.setCancelHandler { close(fd) }
            src.resume()
            self.source = src
            Log.info("native watcher started folder=\(self.folder.path) known=\(self.known.count)")
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func scan() {
        for name in screenshotNames() where !known.contains(name) && !pending.contains(name) {
            pending.insert(name)
            let url = folder.appendingPathComponent(name)
            let detected = Date()
            Log.info("native screenshot detected file=\(name)")
            StableFile.waitUntilStable(interval: 0.3, timeout: 15, queue: queue, size: { StableFile.size(of: url) }) { [weak self] ok in
                guard let self else { return }
                self.pending.remove(name)
                self.known.insert(name)
                guard ok else {
                    Log.info("native screenshot unstable file=\(name)")
                    return
                }
                Log.info("native screenshot stable file=\(name) ms=\(Log.ms(since: detected))")
                let handler = self.onNew
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { handler(url) }
                }
            }
        }
    }

    private func screenshotNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { FileNaming.isNativeScreenshot(name: $0) }
    }
}
