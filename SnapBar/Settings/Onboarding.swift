import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
enum Importer {
    /// Where the plan imports from by default: the Desktop.
    static var defaultSource: URL {
        AppEnvironment.nativeFolderOverride
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    static func candidates(in folder: URL) -> [URL] {
        ShotStore.importCandidates(in: folder).filter { !ShotStore.shared.contains(path: $0.path) }
    }

    /// Asks once, showing the count, then moves the files into the SnapBar folder.
    @discardableResult
    static func importInteractively(from folder: URL) -> Int {
        let files = candidates(in: folder)
        NSApp.activate()
        guard !files.isEmpty else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No screenshots to import")
            alert.runModal()
            return 0
        }
        let destination = AppSettings.shared.saveFolderURL
        let alert = NSAlert()
        alert.messageText = String(localized: "Import \(files.count) screenshots?")
        alert.informativeText = String(localized: "They move from \(folder.lastPathComponent) into \(destination.path) and show up in the library.")
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        Log.info("import dialog shown count=\(files.count) from=\(folder.path)")
        guard alert.runModal() == .alertFirstButtonReturn else {
            Log.info("import cancelled count=\(files.count)")
            return 0
        }
        let added = ShotStore.shared.importFiles(files, into: destination)
        for shot in added { OCRService.shared.recognize(shot: shot) }
        return added.count
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    static let stepCount = 6
    @Published var step = 0 {
        didSet { Log.info("onboarding step=\(step)") }
    }
    @Published var screenGranted = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var desktopCandidates = 0

    func refresh() {
        refreshPermission()
        NotificationsService.shared.authorizationStatus { [weak self] in self?.notificationStatus = $0 }
        desktopCandidates = Importer.candidates(in: Importer.defaultSource).count
    }

    func refreshPermission() {
        let granted = Permissions.screenRecordingGranted
        if granted != screenGranted {
            screenGranted = granted
            Log.info("onboarding screenRecording=\(granted)")
        }
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    let model = OnboardingModel()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
            self?.finish()
        })
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(step: Int = 0) {
        model.step = step
        model.refresh()
        AppWindows.didOpen(window)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        Log.info("onboarding shown step=\(step)")
    }

    private func finish() {
        AppSettings.shared.onboardingCompleted = true
        Log.info("onboarding completed")
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.didClose(window)
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings = AppSettings.shared
    let finish: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: welcome
                case 1: screenRecording
                case 2: notifications
                case 3: folder
                case 4: nativeShots
                default: importStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
            .padding(.top, 44)
            footer
        }
        .frame(width: 620, height: 560)
        .onReceive(timer) { _ in model.refreshPermission() }
        .onAppear { model.refresh() }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<OnboardingModel.stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == model.step ? 18 : 7, height: 7)
                }
            }
            Spacer()
            if model.step > 0 {
                Button("Back") { model.step -= 1 }
            }
            if model.step < OnboardingModel.stepCount - 1 {
                Button("Continue") { model.step += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start Using SnapBar", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func header(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(height: 44)
            Text(title).font(.system(size: 24, weight: .bold))
            Text(text).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to SnapBar").font(.system(size: 28, weight: .bold))
                    Text("Screenshots that paste right away and never get lost.").font(.system(size: 14)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("camera.viewfinder", "⇧⌘S copies and saves", "Every screenshot lands on the clipboard and in one tidy folder at the same time.")
                feature("rectangle.bottomhalf.inset.filled", "A panel that waits for you", "It stays in the corner until you close it or use it. Drag it straight into a chat.")
                feature("photo.on.rectangle.angled", "Every screenshot in one place", "Filter by date, by app, or by words that appear inside the picture.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusPill(_ ok: Bool, _ okText: LocalizedStringKey, _ waitText: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(ok ? okText : waitText)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(ok ? Color.green : Color.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill((ok ? Color.green : Color.orange).opacity(0.14)))
    }

    private var screenRecording: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("rectangle.dashed.badge.record", "Allow screen recording",
                   "macOS asks every app that takes screenshots for this permission. Without it, screenshots come out empty.")
            statusPill(model.screenGranted, "Allowed", "Not allowed yet")
            HStack(spacing: 10) {
                Button("Request Access") {
                    Permissions.requestScreenRecording()
                    Log.info("onboarding requested screen recording")
                }
                Button("Open System Settings") { Permissions.openScreenRecordingSettings() }
            }
            Text("If it stays off after you allow it, quit SnapBar and open it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var notifications: some View {
        let allowed = model.notificationStatus == .authorized || model.notificationStatus == .provisional
        return VStack(alignment: .leading, spacing: 20) {
            header("bell.badge", "Notifications (optional)",
                   "SnapBar uses a notification only if you turn the corner panel off.")
            statusPill(allowed, "Allowed", "Not allowed yet")
            if model.notificationStatus == .notDetermined {
                Button("Allow Notifications") {
                    NotificationsService.shared.requestAuthorization { _ in model.refresh() }
                }
            }
        }
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("folder", "Where screenshots are saved", "One folder for everything. You can change it any time in Settings.")
            HStack(spacing: 10) {
                Image(systemName: "folder.fill").foregroundStyle(Color.accentColor)
                Text(verbatim: settings.saveFolderPath).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { settings.saveFolderPath = url.path }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    private var nativeShots: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("command", "Regular macOS screenshots", "⇧⌘4 keeps working. SnapBar can catch those screenshots too.")
            Toggle("Copy them to the clipboard and library too", isOn: $settings.watchNativeScreenshots)
            Toggle("Save them in the SnapBar folder instead of the Desktop", isOn: $settings.redirectNativeLocation)
            Text("The second switch changes a macOS setting. It stays off unless you turn it on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            header("square.and.arrow.down.on.square", "Tidy up your Desktop",
                   "Move the screenshots already on your Desktop into the SnapBar folder so they show up in the library.")
            if model.desktopCandidates > 0 {
                Text("\(model.desktopCandidates) screenshots found on the Desktop.").font(.system(size: 14, weight: .semibold))
                Button("Import \(model.desktopCandidates) Screenshots…") {
                    Importer.importInteractively(from: Importer.defaultSource)
                    model.refresh()
                }
            } else {
                Text("There are no screenshots on your Desktop to import.").foregroundStyle(.secondary)
            }
        }
    }
}
