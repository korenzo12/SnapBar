import AppKit
import SwiftUI
import UserNotifications

/// Settings with the native macOS toolbar tabs: General, Shortcuts, Panel, Library, Advanced.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private let tabs = NSTabViewController()

    private init() {
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        addTab(GeneralSettingsView(), String(localized: "General"), "gearshape")
        addTab(ShortcutSettingsView(), String(localized: "Shortcuts"), "keyboard")
        addTab(PanelSettingsView(), String(localized: "Panel"), "rectangle.bottomhalf.inset.filled")
        addTab(LibrarySettingsView(), String(localized: "Library"), "photo.on.rectangle")
        addTab(AdvancedSettingsView(), String(localized: "Advanced"), "slider.horizontal.3")
        window.contentViewController = tabs
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func addTab<V: View>(_ view: V, _ title: String, _ symbol: String) {
        let host = NSHostingController(rootView: view.frame(width: 580))
        host.sizingOptions = [.preferredContentSize]
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }

    var selectedTab: Int {
        get { tabs.selectedTabViewItemIndex }
        set { if tabs.tabViewItems.indices.contains(newValue) { tabs.selectedTabViewItemIndex = newValue } }
    }

    func show(tab: Int? = nil) {
        if let tab { selectedTab = tab }
        AppWindows.didOpen(window)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        Log.info("settings open tab=\(selectedTab)")
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.didClose(window)
    }
}

private func displayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

@MainActor
private func chooseFolder(for settings: AppSettings) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = settings.saveFolderURL
    panel.prompt = String(localized: "Choose")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    settings.saveFolderPath = url.path
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    Log.info("settings saveFolder=\(url.path)")
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Screenshots folder") {
                    HStack(spacing: 8) {
                        Text(verbatim: displayPath(settings.saveFolderPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseFolder(for: settings) }
                        Button {
                            NSWorkspace.shared.open(settings.saveFolderURL)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(Text("Show in Finder"))
                    }
                }
                Toggle("Play the shutter sound", isOn: $settings.shutterSound)
                Toggle("Save Retina screenshots at 1x size", isOn: $settings.downscaleRetina)
                Text("Halves the pixel size so files are smaller. Leave it off for full sharpness.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open SnapBar when you log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.set(launchAtLogin) }
            }
            Section("Regular macOS screenshots (⇧⌘4)") {
                Toggle("Copy them to the clipboard and library too", isOn: $settings.watchNativeScreenshots)
                Toggle("Save them in the SnapBar folder", isOn: $settings.redirectNativeLocation)
                Text("This changes where macOS itself saves ⇧⌘4 screenshots. Turn it off to go back to the Desktop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.shutterSound) { Log.info("settings shutterSound=\(settings.shutterSound)") }
        .onChange(of: settings.downscaleRetina) { Log.info("settings downscaleRetina=\(settings.downscaleRetina)") }
        .onChange(of: settings.watchNativeScreenshots) { Log.info("settings watchNative=\(settings.watchNativeScreenshots)") }
        .onChange(of: settings.redirectNativeLocation) { Log.info("settings redirectNative=\(settings.redirectNativeLocation)") }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ShortcutField(title: "Capture an area", name: "captureArea", combo: $settings.captureAreaHotkey)
                ShortcutField(title: "Capture a window", name: "captureWindow", combo: $settings.captureWindowHotkey)
                ShortcutField(title: "Capture the full screen", name: "captureFull", combo: $settings.captureFullHotkey)
                ShortcutField(title: "Open the library", name: "library", combo: $settings.libraryHotkey)
            } footer: {
                Text("Click a shortcut, then press the new keys. Esc cancels and Delete clears it. ⇧⌘4 keeps working as usual.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Default Shortcuts") {
                    settings.captureAreaHotkey = .defaultCaptureArea
                    settings.captureWindowHotkey = nil
                    settings.captureFullHotkey = nil
                    settings.libraryHotkey = .defaultLibrary
                    Log.info("settings shortcuts restored")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PanelSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Toggle("Show a panel in the corner after each screenshot", isOn: $settings.panelEnabled)
                Picker("Corner", selection: $settings.panelCorner) {
                    Text("Bottom left").tag(PanelCorner.bottomLeft)
                    Text("Bottom right").tag(PanelCorner.bottomRight)
                    Text("Top left").tag(PanelCorner.topLeft)
                    Text("Top right").tag(PanelCorner.topRight)
                }
                .disabled(!settings.panelEnabled)
                Picker("Hide automatically", selection: $settings.panelAutoHideSeconds) {
                    Text("Never").tag(0)
                    Text("After 5 seconds").tag(5)
                    Text("After 10 seconds").tag(10)
                    Text("After 30 seconds").tag(30)
                    Text("After 1 minute").tag(60)
                }
                .disabled(!settings.panelEnabled)
            } footer: {
                Text("The panel stays until you close it or use it. Up to five stack in the corner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("When the panel is off") {
                LabeledContent("Notifications") {
                    HStack(spacing: 8) {
                        Text(statusText).foregroundStyle(.secondary)
                        if notificationStatus == .notDetermined {
                            Button("Allow…") {
                                NotificationsService.shared.requestAuthorization { _ in refresh() }
                            }
                        } else if notificationStatus == .denied {
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: settings.panelEnabled) { Log.info("settings panelEnabled=\(settings.panelEnabled)") }
        .onChange(of: settings.panelCorner) { Log.info("settings panelCorner=\(settings.panelCorner.rawValue)") }
        .onChange(of: settings.panelAutoHideSeconds) { Log.info("settings panelAutoHide=\(settings.panelAutoHideSeconds)") }
    }

    private var statusText: LocalizedStringKey {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Not allowed"
        default: return "Not asked yet"
        }
    }

    private func refresh() {
        NotificationsService.shared.authorizationStatus { notificationStatus = $0 }
    }
}

struct LibrarySettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store = ShotStore.shared
    @State private var desktopCount = 0

    var body: some View {
        Form {
            Section {
                LabeledContent("Screenshots in the library") {
                    Text(verbatim: "\(store.shots.count)").monospacedDigit()
                }
                Picker("Move old screenshots to the Trash", selection: $settings.retentionDays) {
                    Text("Never").tag(0)
                    Text("After 7 days").tag(7)
                    Text("After 30 days").tag(30)
                    Text("After 90 days").tag(90)
                    Text("After a year").tag(365)
                }
                Text("Favorites are always kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Import") {
                LabeledContent("Screenshots on the Desktop") {
                    Text(verbatim: "\(desktopCount)").monospacedDigit()
                }
                Button("Import Screenshots from the Desktop…") {
                    Importer.importInteractively(from: Importer.defaultSource)
                    refresh()
                }
                .disabled(desktopCount == 0)
            }
            Section("Maintenance") {
                Button("Rebuild Thumbnails") {
                    ThumbnailCache.shared.removeAll()
                    Log.info("settings thumbnails rebuilt")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: settings.retentionDays) {
            Log.info("settings retentionDays=\(settings.retentionDays)")
            store.applyRetention(days: settings.retentionDays)
        }
    }

    private func refresh() {
        desktopCount = Importer.candidates(in: Importer.defaultSource).count
    }
}

struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section("Files") {
                LabeledContent("Log") {
                    Button("Open Log File") { NSWorkspace.shared.open(Log.shared.fileURL) }
                }
                LabeledContent("Library index") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([ShotStore.defaultIndexURL])
                    }
                }
            }
            Section("Help") {
                Button("Show the Welcome Guide Again") { OnboardingWindowController.shared.show() }
            }
            Section {
                LabeledContent("Version") {
                    Text(verbatim: "SnapBar \(Bundle.main.shortVersion)").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
