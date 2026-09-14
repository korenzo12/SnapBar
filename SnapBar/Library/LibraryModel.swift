import AppKit
import Combine

extension DateFilter {
    var logName: String {
        switch self {
        case .all: return "all"
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .last7Days: return "last7"
        case .last30Days: return "last30"
        case .thisMonth: return "thisMonth"
        case .custom: return "custom"
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

/// State behind the library window: the query, what it matches, and the selection.
@MainActor
final class LibraryModel: ObservableObject {
    let store: ShotStore
    let settings: AppSettings

    @Published var query = LibraryQuery() {
        didSet { if query != oldValue { recompute() } }
    }
    @Published var customFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var customTo = Date()
    @Published private(set) var visible: [Shot] = []
    @Published private(set) var sections: [ShotSection] = []
    @Published var selection: Set<UUID> = []

    private var cancellables = Set<AnyCancellable>()
    private var iconCache: [String: NSImage] = [:]

    convenience init() {
        self.init(store: .shared, settings: .shared)
    }

    init(store: ShotStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        store.$shots
            .sink { [weak self] shots in self?.recompute(shots) }
            .store(in: &cancellables)
    }

    func recompute(_ all: [Shot]? = nil) {
        let shots = all ?? store.shots
        visible = query.apply(to: shots)
        sections = LibraryQuery.sections(visible, sort: query.sort)
        let ids = Set(visible.map(\.id))
        if !selection.isSubset(of: ids) { selection = selection.intersection(ids) }
    }

    var selectedShots: [Shot] { visible.filter { selection.contains($0.id) } }

    // MARK: Sidebar counts

    func count(for filter: DateFilter) -> Int {
        let now = Date()
        return store.shots.reduce(0) { $0 + (filter.contains($1.createdAt, now: now) ? 1 : 0) }
    }

    func count(for source: ShotSource) -> Int {
        store.shots.reduce(0) { $0 + ($1.source == source ? 1 : 0) }
    }

    var favoritesCount: Int { store.shots.reduce(0) { $0 + ($1.favorite ? 1 : 0) } }

    var apps: [(name: String, count: Int)] { LibraryQuery.appCounts(store.shots) }

    func icon(forApp name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        guard let bundleID = store.shots.first(where: { $0.appName == name })?.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[name] = icon
        return icon
    }

    // MARK: Filter changes

    func setDateFilter(_ filter: DateFilter) {
        query.dateFilter = filter
        Log.info("library filter date=\(filter.logName) results=\(visible.count)")
    }

    func applyCustomRange() {
        query.dateFilter = .custom(from: customFrom, to: customTo)
        Log.info("library filter date=custom from=\(customFrom) to=\(customTo) results=\(visible.count)")
    }

    func toggleSource(_ source: ShotSource) {
        if query.sources.contains(source) { query.sources.remove(source) } else { query.sources.insert(source) }
        Log.info("library filter sources=\(query.sources.map(\.rawValue).sorted().joined(separator: ",")) results=\(visible.count)")
    }

    func selectApp(_ name: String?) {
        query.appName = name
        Log.info("library filter app=\(name ?? "all") results=\(visible.count)")
    }

    func toggleFavoritesOnly() {
        query.favoritesOnly.toggle()
        Log.info("library filter favorites=\(query.favoritesOnly) results=\(visible.count)")
    }

    func setSort(_ sort: ShotSort) {
        query.sort = sort
        Log.info("library sort=\(sort.rawValue)")
    }

    func setSearch(_ text: String) {
        query.searchText = text
    }

    func clearFilters() {
        query = LibraryQuery(sort: query.sort)
    }
}
