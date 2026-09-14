import AppKit
import Combine

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
}

/// Owns the menu bar item, the global shortcuts and the long-lived services.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var current: AppDelegate?

    let settings = AppSettings.shared
    let store = ShotStore.shared
    private(set) var capture: CaptureService?
    private var statusItem: NSStatusItem?
    private var nativeWatcher: NativeWatcher?
    private var cancellables = Set<AnyCancellable>()

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.current = self
        guard !AppDelegate.isRunningTests else { return }
        Log.info("launch version=\(Bundle.main.shortVersion) pid=\(ProcessInfo.processInfo.processIdentifier) path=\(Bundle.main.bundlePath)")
        try? FileManager.default.createDirectory(at: settings.saveFolderURL, withIntermediateDirectories: true)
        NSApp.mainMenu = MainMenu.build()
        #if DEBUG
        DebugHooks.install()
        #endif
        store.load()
        capture = CaptureService(settings: settings, store: store)
        buildStatusItem()
        bindHotkeys()
        bindNativeWatcher()
        store.applyRetention(days: settings.retentionDays)
        NotificationsService.shared.configure()
        LaunchAtLogin.logStatus()
        Log.info("activationPolicy=\(NSApp.activationPolicy() == .regular ? "regular" : "accessory")")
        if !settings.onboardingCompleted {
            OnboardingWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LibraryWindowController.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        Log.info("terminate")
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapBar")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SnapBar"
        }
        statusItem = item
        rebuildMenu()
        Log.info("status item installed")
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        addItem(menu, String(localized: "Capture Area"), #selector(captureArea), settings.captureAreaHotkey)
        addItem(menu, String(localized: "Capture Window"), #selector(captureWindow), settings.captureWindowHotkey)
        addItem(menu, String(localized: "Capture Full Screen"), #selector(captureFullScreen), settings.captureFullHotkey)
        menu.addItem(.separator())
        addItem(menu, String(localized: "Screenshot Library…"), #selector(openLibrary), settings.libraryHotkey)
        addItem(menu, String(localized: "Open Screenshots Folder"), #selector(openFolder), nil)
        menu.addItem(.separator())
        let settingsItem = addItem(menu, String(localized: "Settings…"), #selector(openSettings), nil)
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(.separator())
        let quitItem = addItem(menu, String(localized: "Quit SnapBar"), #selector(quit), nil)
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        statusItem?.menu = menu
        Log.info("menu built items=\(menu.items.filter { !$0.isSeparatorItem }.count)")
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ combo: KeyCombo?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: combo?.menuKeyEquivalent ?? "")
        if let combo { item.keyEquivalentModifierMask = combo.eventModifierFlags }
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: Shortcuts

    private func bindHotkeys() {
        settings.$captureAreaHotkey
            .combineLatest(settings.$captureWindowHotkey, settings.$captureFullHotkey, settings.$libraryHotkey)
            .sink { [weak self] area, window, full, library in
                self?.registerHotkeys(area: area, window: window, full: full, library: library)
            }
            .store(in: &cancellables)
    }

    private func registerHotkeys(area: KeyCombo?, window: KeyCombo?, full: KeyCombo?, library: KeyCombo?) {
        let hotkeys = HotkeyManager.shared
        hotkeys.unregisterAll()
        if let area { hotkeys.register(area, name: "captureArea") { [weak self] in self?.captureArea() } }
        if let window { hotkeys.register(window, name: "captureWindow") { [weak self] in self?.captureWindow() } }
        if let full { hotkeys.register(full, name: "captureFull") { [weak self] in self?.captureFullScreen() } }
        if let library { hotkeys.register(library, name: "library") { [weak self] in self?.openLibrary() } }
        if statusItem != nil { rebuildMenu() }
    }

    // MARK: Native ⌘⇧4 screenshots

    private func bindNativeWatcher() {
        settings.$watchNativeScreenshots
            .combineLatest(settings.$redirectNativeLocation, settings.$saveFolderPath)
            .sink { [weak self] watch, redirect, folder in
                self?.configureNative(watch: watch, redirect: redirect, folderPath: folder)
            }
            .store(in: &cancellables)
    }

    private var lastRedirect: Bool?
    private var lastFolder: String?

    /// Values arrive from the publishers directly: @Published fires before the property itself changes.
    private func configureNative(watch: Bool, redirect: Bool, folderPath: String) {
        let folderURL = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
        if let previous = lastRedirect, previous != redirect || (redirect && lastFolder != folderPath) {
            NativeLocation.apply(folder: redirect ? folderURL : nil)
        }
        lastRedirect = redirect
        lastFolder = folderPath
        nativeWatcher?.stop()
        nativeWatcher = nil
        guard watch else {
            Log.info("native watcher off")
            return
        }
        let folder = redirect ? folderURL : (AppEnvironment.nativeFolderOverride ?? FileNaming.systemScreenshotFolder())
        let watcher = NativeWatcher(folder: folder) { [weak self] url in
            self?.capture?.ingestNative(url: url)
        }
        watcher.start()
        nativeWatcher = watcher
    }

    // MARK: Actions

    @objc func captureArea() { capture?.capture(.area) }
    @objc func captureWindow() { capture?.capture(.window) }
    @objc func captureFullScreen() { capture?.capture(.fullScreen) }
    @objc func openLibrary() { LibraryWindowController.shared.show() }
    @objc func openFolder() { NSWorkspace.shared.open(settings.saveFolderURL) }
    @objc func openSettings() { SettingsWindowController.shared.show() }
    @objc func quit() { NSApp.terminate(nil) }
}

#if DEBUG
extension AppDelegate {
    func debugMenuDump() {
        for item in statusItem?.menu?.items ?? [] where !item.isSeparatorItem {
            Log.info("menu item title=\(item.title) key=\(item.keyEquivalent) mods=\(item.keyEquivalentModifierMask.rawValue)")
        }
        let frame = statusItem?.button?.window?.frame ?? .zero
        Log.info("status item frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)) dockIcon=\(NSApp.activationPolicy() == .regular)")
    }

    func debugOpenMenu() {
        statusItem?.button?.performClick(nil)
    }
}
#endif
