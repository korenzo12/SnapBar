#if DEBUG
import AppKit

/// Test automation for the proof ledger. Compiled only into Debug builds, never into Release.
/// Drive a running Debug build from a shell with `scripts/snapctl <command> [arg] [app]`.
@MainActor
enum DebugHooks {
    static let name = Notification.Name("co.il.ckdigital360.snapbar.debug")
    private static var observer: NSObjectProtocol?

    static func install() {
        observer = DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            let command = note.object as? String ?? ""
            let arg = note.userInfo?["arg"] as? String ?? ""
            let app = note.userInfo?["app"] as? String ?? ""
            MainActor.assumeIsolated { run(command, arg, app) }
        }
        Log.info("debug hooks installed home=\(AppEnvironment.home?.path ?? "-") native=\(AppEnvironment.nativeFolderOverride?.path ?? "-")")
    }

    static func run(_ command: String, _ arg: String, _ app: String) {
        Log.info("debug command=\(command) arg=\(arg)")
        let delegate = AppDelegate.current
        switch command {
        case "snapshot": snapshot(prefix: arg)
        case "library": LibraryWindowController.shared.show()
        case "closeLibrary": LibraryWindowController.shared.window?.close()
        case "settings": SettingsWindowController.shared.show(tab: Int(arg) ?? 0)
        case "closeSettings": SettingsWindowController.shared.window?.close()
        case "onboarding": OnboardingWindowController.shared.show(step: Int(arg) ?? 0)
        case "closeOnboarding": OnboardingWindowController.shared.window?.close()
        case "ingest":
            delegate?.capture?.ingest(url: URL(fileURLWithPath: arg), source: .snapbar,
                                      appName: app.isEmpty ? "Safari" : app, bundleID: nil, since: Date())
        case "ingestNative": delegate?.capture?.ingestNative(url: URL(fileURLWithPath: arg))
        case "capture": delegate?.capture?.capture(CaptureMode(rawValue: arg) ?? .area)
        case "hotkey": HotkeyManager.shared.fireForTest(name: arg)
        case "menuDump": delegate?.debugMenuDump()
        case "menu": delegate?.debugOpenMenu()
        case "panel": panel(arg)
        case "filter": LibraryWindowController.shared.debugFilter(arg)
        case "select": LibraryWindowController.shared.debugSelect(count: Int(arg) ?? 1)
        case "quicklook": LibraryWindowController.shared.debugQuickLook()
        case "copySelection": LibraryWindowController.shared.debugCopySelection()
        case "contextMenu": LibraryWindowController.shared.debugContextMenu()
        case "gridDump": LibraryWindowController.shared.debugGrid()
        case "exportSelection": LibraryWindowController.shared.debugExportSelection(to: arg)
        case "trashSelection": LibraryWindowController.shared.debugTrashSelection()
        case "favoriteSelection": LibraryWindowController.shared.debugFavoriteSelection()
        case "editor":
            let shots = ShotStore.shared.shots
            let index = min(max(Int(arg) ?? 0, 0), max(shots.count - 1, 0))
            if shots.indices.contains(index) { EditorWindowController.open(shot: shots[index]) }
        case "editorDemo": EditorWindowController.debugCurrent?.debugDemo(text: arg.isEmpty ? "כאן הירידה" : arg)
        case "editorCrop":
            let v = arg.split(separator: ",").compactMap { Double($0) }
            if v.count == 4 { EditorWindowController.debugCurrent?.debugCrop(CGRect(x: v[0], y: v[1], width: v[2], height: v[3])) }
        case "editorZoom": EditorWindowController.debugCurrent?.debugZoom(Double(arg) ?? 1)
        case "editorTool": EditorWindowController.debugCurrent?.debugTool(arg)
        case "editorCopy": EditorWindowController.debugCurrent?.debugCopy()
        case "editorExport": EditorWindowController.debugCurrent?.debugExport(to: arg)
        case "editorUndoRedo": EditorWindowController.debugCurrent?.debugUndoRedo()
        case "closeEditor": EditorWindowController.debugCurrent?.window?.close()
        case "appearance":
            NSApp.appearance = arg == "dark" ? NSAppearance(named: .darkAqua) : (arg == "light" ? NSAppearance(named: .aqua) : nil)
            Log.info("debug appearance=\(arg) systemStyle=\(UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light")")
        case "stack": stack(arg)
        case "importCount": Log.info("import candidates=\(Importer.candidates(in: Importer.defaultSource).count) from=\(Importer.defaultSource.path)")
        case "state": state()
        case "quit": NSApp.terminate(nil)
        case "script": script(arg)
        case "set": set(arg)
        case "login":
            LaunchAtLogin.set(arg == "true")
            LaunchAtLogin.logStatus()
        case "backdate": backdate(arg)
        case "importAsk": Importer.importInteractively(from: Importer.defaultSource)
        case "modal":
            NSApp.stopModal(withCode: arg == "cancel" ? .alertSecondButtonReturn : .alertFirstButtonReturn)
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(wake, atStart: true)
            }
        default: Log.info("debug unknown command=\(command)")
        }
    }

    /// "cmd arg ;; cmd arg || AppName ;; ..." runs each step 700 ms apart, so views finish drawing
    /// before the next snapshot. The shell cannot sleep, so the app keeps the time.
    private static func script(_ text: String) {
        let steps = text.components(separatedBy: " ;; ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700 * i)) {
                MainActor.assumeIsolated {
                    let pieces = step.components(separatedBy: " || ")
                    let parts = pieces[0].split(separator: " ", maxSplits: 1).map(String.init)
                    run(parts.first ?? "", parts.count > 1 ? parts[1] : "", pieces.count > 1 ? pieces[1] : "")
                }
            }
        }
        Log.info("debug script steps=\(steps.count)")
    }

    /// "N|yyyy-MM-dd HH:mm": moves the Nth newest shot to another date, to fill the library across days.
    private static func backdate(_ spec: String) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        let f = DateFormatter()
        f.calendar = .snapbar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        guard parts.count == 2, let index = Int(parts[0]), let date = f.date(from: parts[1]),
              ShotStore.shared.shots.indices.contains(index) else { return }
        ShotStore.shared.update(ShotStore.shared.shots[index].id) { $0.createdAt = date }
        Log.info("debug backdate index=\(index) date=\(parts[1])")
    }

    /// "key value": changes a setting live, e.g. "panelAutoHideSeconds 5" or "shutterSound false".
    private static func set(_ spec: String) {
        let parts = spec.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let settings = AppSettings.shared
        let flag = parts[1] == "true"
        switch parts[0] {
        case "shutterSound": settings.shutterSound = flag
        case "downscaleRetina": settings.downscaleRetina = flag
        case "panelEnabled": settings.panelEnabled = flag
        case "watchNativeScreenshots": settings.watchNativeScreenshots = flag
        case "redirectNativeLocation": settings.redirectNativeLocation = flag
        case "panelAutoHideSeconds": settings.panelAutoHideSeconds = Int(parts[1]) ?? 0
        case "retentionDays": settings.retentionDays = Int(parts[1]) ?? 0
        case "panelCorner": if let c = PanelCorner(rawValue: parts[1]) { settings.panelCorner = c }
        default:
            Log.info("debug set unknown key=\(parts[0])")
            return
        }
        Log.info("debug set \(parts[0])=\(parts[1])")
    }

    private static func panel(_ action: String) {
        guard let newest = PanelController.shared.panels.last else {
            Log.info("debug no panel")
            return
        }
        switch action {
        case "close": PanelController.shared.dismiss(newest, reason: "close")
        case "escape": newest.cancelOperation(nil)
        default:
            if let a = PanelAction(rawValue: action) { PanelController.shared.perform(a, on: newest) }
        }
    }

    /// "N|/path/sample.png": copies the sample N times and ingests each copy, 400 ms apart.
    private static func stack(_ spec: String) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let count = Int(parts[0]) else { return }
        let sample = URL(fileURLWithPath: parts[1])
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400 * i)) {
                MainActor.assumeIsolated {
                    let folder = AppSettings.shared.saveFolderURL
                    let dest = FileNaming.uniqueURL(in: folder, fileName: "SnapBar stack \(i + 1).png")
                    try? FileManager.default.copyItem(at: sample, to: dest)
                    AppDelegate.current?.capture?.ingest(url: dest, source: .snapbar, appName: "Stack \(i + 1)", bundleID: nil, since: Date())
                }
            }
        }
    }

    private static func state() {
        let windows = NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))[\($0.title)]" }
        Log.info("debug state panels=\(PanelController.shared.panels.count) shots=\(ShotStore.shared.shots.count) windows=\(windows.joined(separator: ",")) policy=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory") key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "-")")
    }

    /// Renders every visible SnapBar window (panels included) into PNGs, without Screen Recording permission.
    private static func snapshot(prefix: String) {
        var n = 0
        for window in NSApp.windows where window.isVisible && window.frame.width > 40 {
            guard let view = window.contentView?.superview ?? window.contentView else { continue }
            let bounds = view.bounds
            guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            // cacheDisplay misses layer-backed content such as the collection view's thumbnails,
            // so render the layer tree when there is one.
            if let layer = view.layer, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                ctx.cgContext.clear(CGRect(origin: .zero, size: bounds.size))
                layer.render(in: ctx.cgContext)
            } else {
                view.cacheDisplay(in: bounds, to: rep)
            }
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            n += 1
            let label = window.title.isEmpty ? String(describing: type(of: window)) : window.title
            let safe = label.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "_")
            let url = URL(fileURLWithPath: "\(prefix)-\(n)-\(safe).png")
            try? data.write(to: url)
            Log.info("debug snapshot file=\(url.lastPathComponent) window=\(label) size=\(Int(bounds.width))x\(Int(bounds.height))")
        }
        if n == 0 { Log.info("debug snapshot none visible") }
    }
}
#endif
