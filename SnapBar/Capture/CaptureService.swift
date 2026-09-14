import AppKit

enum CaptureMode: String, Sendable {
    case area, window, fullScreen
}

/// Runs macOS's own `screencapture`, then fans each result out to the file, the clipboard,
/// the library, the corner panel and OCR.
@MainActor
final class CaptureService {
    let settings: AppSettings
    let store: ShotStore
    private var running: Process?
    /// macOS naps a background menu bar app, which delayed launching the capture tool by many seconds.
    private var activity: NSObjectProtocol?
    /// The clipboard always holds the newest screenshot, even if an older one finishes writing later.
    private var clipboardShotDate: Date?

    init(settings: AppSettings, store: ShotStore) {
        self.settings = settings
        self.store = store
    }

    nonisolated static func arguments(mode: CaptureMode, sound: Bool, output: String) -> [String] {
        var args: [String] = []
        switch mode {
        case .area: args.append("-i")
        case .window: args += ["-i", "-W"]
        case .fullScreen: args.append("-m")
        }
        if !sound { args.append("-x") }
        args.append(output)
        return args
    }

    func capture(_ mode: CaptureMode) {
        // A capture whose process already died must never block the next one.
        if let previous = running, !previous.isRunning {
            Log.info("capture cleared stale process pid=\(previous.processIdentifier)")
            finishedRunning()
        }
        guard running == nil else {
            Log.info("capture ignored reason=already-running")
            return
        }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "SnapBar capture")
        if !Permissions.screenRecordingGranted {
            Log.info("capture preflight screenRecording=false")
        }
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName
        let bundleID = front?.bundleIdentifier
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapbar-\(UUID().uuidString).png")
        let args = CaptureService.arguments(mode: mode, sound: settings.shutterSound, output: tmp.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppEnvironment.captureTool ?? "/usr/sbin/screencapture")
        process.arguments = args
        Log.info("capture start tool=\(process.executableURL?.lastPathComponent ?? "-") mode=\(mode.rawValue) args=\(args.dropLast().joined(separator: " ")) app=\(appName ?? "-")")
        let launched = Date()
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let ended = Date()
            Log.info("capture tool finished status=\(status) toolMs=\(Log.ms(since: launched))")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finish(tmp: tmp, status: status, ended: ended, mode: mode, appName: appName, bundleID: bundleID)
                }
            }
        }
        do {
            try process.run()
            running = process
        } catch {
            Log.info("capture launch failed error=\(error.localizedDescription)")
            finishedRunning()
        }
    }

    private func finishedRunning() {
        running = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func finish(tmp: URL, status: Int32, ended: Date, mode: CaptureMode, appName: String?, bundleID: String?) {
        finishedRunning()
        guard FileManager.default.fileExists(atPath: tmp.path) else {
            Log.info("capture cancelled mode=\(mode.rawValue) status=\(status)")
            return
        }
        let folder = settings.saveFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = FileNaming.uniqueURL(in: folder, fileName: FileNaming.captureFileName(for: ended))
        do {
            try FileManager.default.moveItem(at: tmp, to: dest)
        } catch {
            Log.info("capture move failed error=\(error.localizedDescription)")
            return
        }
        if settings.downscaleRetina {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            if let size = ImageTools.downscale(url: dest, by: scale) {
                Log.info("downscale scale=\(scale) result=\(Int(size.width))x\(Int(size.height))")
            }
        }
        ingest(url: dest, source: .snapbar, appName: appName, bundleID: bundleID, since: ended, createdAt: ended)
    }

    /// A ⌘⇧4 screenshot macOS just finished writing.
    func ingestNative(url: URL) {
        guard !store.contains(path: url.path) else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        ingest(url: url, source: .native, appName: front?.localizedName, bundleID: front?.bundleIdentifier,
               since: Date(), createdAt: created)
    }

    func ingest(url: URL, source: ShotSource, appName: String?, bundleID: String?, since start: Date,
                createdAt: Date = Date()) {
        // Paste right after a capture must give that capture, so only a newer shot may take the clipboard.
        if let previous = clipboardShotDate, createdAt < previous {
            Log.info("clipboard kept newer shot, skipped file=\(url.lastPathComponent)")
        } else {
            let copied = Clipboard.write(fileURL: url)
            clipboardShotDate = createdAt
            Log.info("clipboard written ok=\(copied) source=\(source.rawValue) ms=\(Log.ms(since: start)) file=\(url.lastPathComponent)")
        }
        let info = ImageTools.info(url: url)
        let shot = Shot(path: url.path, createdAt: createdAt, source: source, appName: appName, appBundleID: bundleID,
                        pixelWidth: info?.width ?? 0, pixelHeight: info?.height ?? 0, fileSize: info?.fileSize ?? 0)
        let stored = store.add(shot) ?? shot
        Log.info("history added id=\(stored.id.uuidString) source=\(source.rawValue) size=\(stored.pixelWidth)x\(stored.pixelHeight) new=\(stored.id == shot.id)")
        PanelController.shared.present(shot: stored, since: start)
        if let thumb = ImageTools.thumbnail(url: url, maxPixel: 64), ImageTools.isBlank(thumb) {
            Log.info("capture blank, permission alert shown")
            Permissions.showBlankCaptureAlert()
        }
        OCRService.shared.recognize(shot: stored)
    }
}
