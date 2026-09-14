import Combine
import Foundation

enum PanelCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottomLeft, bottomRight, topLeft, topRight
    var id: String { rawValue }
}

/// Every user preference, persisted to UserDefaults. Injectable defaults keep it testable.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings(defaults: AppEnvironment.home == nil
        ? .standard : (UserDefaults(suiteName: "co.il.ckdigital360.snapbar.dev") ?? .standard))

    enum Keys {
        static let captureArea = "hotkey.captureArea"
        static let captureWindow = "hotkey.captureWindow"
        static let captureFull = "hotkey.captureFull"
        static let library = "hotkey.library"
        static let saveFolder = "saveFolderPath"
        static let downscale = "downscaleRetina"
        static let shutter = "shutterSound"
        static let panelEnabled = "panelEnabled"
        static let panelCorner = "panelCorner"
        static let panelAutoHide = "panelAutoHideSeconds"
        static let watchNative = "watchNativeScreenshots"
        static let redirectNative = "redirectNativeLocation"
        static let retentionDays = "retentionDays"
        static let thumbnailSize = "thumbnailSize"
        static let onboarding = "onboardingCompleted"
    }

    let defaults: UserDefaults

    @Published var captureAreaHotkey: KeyCombo? { didSet { saveCombo(captureAreaHotkey, Keys.captureArea) } }
    @Published var captureWindowHotkey: KeyCombo? { didSet { saveCombo(captureWindowHotkey, Keys.captureWindow) } }
    @Published var captureFullHotkey: KeyCombo? { didSet { saveCombo(captureFullHotkey, Keys.captureFull) } }
    @Published var libraryHotkey: KeyCombo? { didSet { saveCombo(libraryHotkey, Keys.library) } }
    @Published var saveFolderPath: String { didSet { defaults.set(saveFolderPath, forKey: Keys.saveFolder) } }
    @Published var downscaleRetina: Bool { didSet { defaults.set(downscaleRetina, forKey: Keys.downscale) } }
    @Published var shutterSound: Bool { didSet { defaults.set(shutterSound, forKey: Keys.shutter) } }
    @Published var panelEnabled: Bool { didSet { defaults.set(panelEnabled, forKey: Keys.panelEnabled) } }
    @Published var panelCorner: PanelCorner { didSet { defaults.set(panelCorner.rawValue, forKey: Keys.panelCorner) } }
    @Published var panelAutoHideSeconds: Int { didSet { defaults.set(panelAutoHideSeconds, forKey: Keys.panelAutoHide) } }
    @Published var watchNativeScreenshots: Bool { didSet { defaults.set(watchNativeScreenshots, forKey: Keys.watchNative) } }
    @Published var redirectNativeLocation: Bool { didSet { defaults.set(redirectNativeLocation, forKey: Keys.redirectNative) } }
    @Published var retentionDays: Int { didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) } }
    @Published var thumbnailSize: Double { didSet { defaults.set(thumbnailSize, forKey: Keys.thumbnailSize) } }
    @Published var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Keys.onboarding) } }

    static var defaultSaveFolder: String {
        if let home = AppEnvironment.home { return home.appendingPathComponent("Screenshots", isDirectory: true).path }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Screenshots", isDirectory: true).path
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureAreaHotkey = AppSettings.loadCombo(defaults, Keys.captureArea, fallback: .defaultCaptureArea)
        captureWindowHotkey = AppSettings.loadCombo(defaults, Keys.captureWindow, fallback: nil)
        captureFullHotkey = AppSettings.loadCombo(defaults, Keys.captureFull, fallback: nil)
        libraryHotkey = AppSettings.loadCombo(defaults, Keys.library, fallback: .defaultLibrary)
        saveFolderPath = defaults.string(forKey: Keys.saveFolder) ?? AppSettings.defaultSaveFolder
        downscaleRetina = defaults.object(forKey: Keys.downscale) as? Bool ?? false
        shutterSound = defaults.object(forKey: Keys.shutter) as? Bool ?? true
        panelEnabled = defaults.object(forKey: Keys.panelEnabled) as? Bool ?? true
        panelCorner = PanelCorner(rawValue: defaults.string(forKey: Keys.panelCorner) ?? "") ?? .bottomLeft
        panelAutoHideSeconds = defaults.object(forKey: Keys.panelAutoHide) as? Int ?? 0
        watchNativeScreenshots = defaults.object(forKey: Keys.watchNative) as? Bool ?? true
        redirectNativeLocation = defaults.object(forKey: Keys.redirectNative) as? Bool ?? false
        retentionDays = defaults.object(forKey: Keys.retentionDays) as? Int ?? 0
        thumbnailSize = defaults.object(forKey: Keys.thumbnailSize) as? Double ?? 180
        onboardingCompleted = defaults.object(forKey: Keys.onboarding) as? Bool ?? false
    }

    var saveFolderURL: URL {
        URL(fileURLWithPath: (saveFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func saveCombo(_ combo: KeyCombo?, _ key: String) {
        if let data = try? JSONEncoder().encode(combo) { defaults.set(data, forKey: key) }
    }

    /// An explicit `null` means the user cleared the shortcut, so it must not fall back.
    private static func loadCombo(_ d: UserDefaults, _ key: String, fallback: KeyCombo?) -> KeyCombo? {
        guard let data = d.data(forKey: key) else { return fallback }
        do { return try JSONDecoder().decode(KeyCombo?.self, from: data) } catch { return fallback }
    }
}
