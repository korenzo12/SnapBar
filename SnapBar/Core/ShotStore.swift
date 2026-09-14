import AppKit
import Combine

/// The library index: `history.json` in Application Support. Images stay where they are on disk.
@MainActor
final class ShotStore: ObservableObject {
    static let shared = ShotStore()

    @Published private(set) var shots: [Shot] = []
    let indexURL: URL
    private let saveQueue = DispatchQueue(label: "co.il.ckdigital360.snapbar.index")
    private var saveWork: DispatchWorkItem?

    init(indexURL: URL = ShotStore.defaultIndexURL) {
        self.indexURL = indexURL
    }

    nonisolated static var supportDirectory: URL {
        if let home = AppEnvironment.home { return home.appendingPathComponent("Support", isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SnapBar", isDirectory: true)
    }

    nonisolated static var defaultIndexURL: URL { supportDirectory.appendingPathComponent("history.json") }

    // MARK: Load and save

    /// Loads the index and drops entries whose files were deleted outside SnapBar.
    func load() {
        let start = Date()
        guard let data = try? Data(contentsOf: indexURL) else {
            shots = []
            Log.info("index load count=0 pruned=0 new=true")
            return
        }
        do {
            let decoded = try JSONDecoder().decode([Shot].self, from: data)
            let alive = decoded.filter { FileManager.default.fileExists(atPath: $0.path) && FileNaming.isImageFile($0.url) }
            shots = LibraryQuery.sorted(alive, by: .newestFirst)
            let pruned = decoded.count - alive.count
            if pruned > 0 { saveNow() }
            Log.info("index load count=\(alive.count) pruned=\(pruned) ms=\(Log.ms(since: start))")
        } catch {
            Log.info("index load failed error=\(error.localizedDescription)")
        }
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        let snapshot = shots
        let url = indexURL
        saveQueue.async { ShotStore.write(snapshot, to: url) }
    }

    /// Synchronous save, for tests and termination.
    func saveNowAndWait() {
        saveWork?.cancel()
        saveWork = nil
        let snapshot = shots
        let url = indexURL
        saveQueue.sync { ShotStore.write(snapshot, to: url) }
    }

    nonisolated private static func write(_ shots: [Shot], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(shots)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.info("index save failed error=\(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Mutations

    /// Returns the record the library actually holds: the existing one when this file is already
    /// indexed, so callers never act on a record the library does not have.
    @discardableResult
    func add(_ shot: Shot) -> Shot? {
        guard FileNaming.isImageFile(shot.url) else { return nil }
        if let existing = shots.first(where: { $0.path == shot.path }) { return existing }
        shots.insert(shot, at: 0)
        scheduleSave()
        return shot
    }

    func contains(path: String) -> Bool {
        shots.contains { $0.path == path }
    }

    func shot(id: UUID) -> Shot? {
        shots.first { $0.id == id }
    }

    func update(_ id: UUID, _ change: (inout Shot) -> Void) {
        guard let i = shots.firstIndex(where: { $0.id == id }) else { return }
        change(&shots[i])
        scheduleSave()
    }

    func setOCR(_ id: UUID, text: String) {
        update(id) { $0.ocrText = text }
    }

    func setFavorite(_ ids: Set<UUID>, _ value: Bool) {
        for i in shots.indices where ids.contains(shots[i].id) { shots[i].favorite = value }
        scheduleSave()
        Log.info("favorite set=\(value) count=\(ids.count)")
    }

    /// Removes entries; with `trashFiles` the images go to the Trash (never deleted outright).
    @discardableResult
    func remove(ids: Set<UUID>, trashFiles: Bool) -> Int {
        var trashed = 0
        if trashFiles {
            for shot in shots where ids.contains(shot.id) {
                do {
                    try FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
                    trashed += 1
                } catch {
                    Log.info("trash failed file=\(shot.fileName) error=\(error.localizedDescription)")
                }
            }
        }
        shots.removeAll { ids.contains($0.id) }
        scheduleSave()
        Log.info("history removed count=\(ids.count) trashed=\(trashed)")
        return trashed
    }

    func applyRetention(days: Int, now: Date = Date()) {
        let expired = LibraryQuery.expired(shots, now: now, retentionDays: days)
        guard !expired.isEmpty else { return }
        remove(ids: Set(expired.map(\.id)), trashFiles: true)
        Log.info("retention removed=\(expired.count) days=\(days)")
    }

    // MARK: Import

    static func importCandidates(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { FileNaming.isNativeScreenshot(name: $0) }.map { folder.appendingPathComponent($0) }
    }

    /// Moves the given screenshots into `destination` and indexes them as imported.
    @discardableResult
    func importFiles(_ files: [URL], into destination: URL) -> [Shot] {
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var added: [Shot] = []
        for url in files {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            let inPlace = url.deletingLastPathComponent().standardizedFileURL.path == destination.standardizedFileURL.path
            let target = inPlace ? url : FileNaming.uniqueURL(in: destination, fileName: url.lastPathComponent)
            guard !contains(path: target.path) else { continue }
            if !inPlace {
                do {
                    try FileManager.default.moveItem(at: url, to: target)
                } catch {
                    Log.info("import move failed file=\(url.lastPathComponent) error=\(error.localizedDescription)")
                    continue
                }
            }
            let info = ImageTools.info(url: target)
            let shot = Shot(path: target.path, createdAt: created, source: .imported,
                            pixelWidth: info?.width ?? 0, pixelHeight: info?.height ?? 0, fileSize: info?.fileSize ?? 0)
            added.append(shot)
        }
        shots = LibraryQuery.sorted(shots + added, by: .newestFirst)
        scheduleSave()
        Log.info("import moved=\(added.count) of=\(files.count) into=\(destination.path)")
        return added
    }
}
