import Combine
import AppKit
import SwiftUI

extension NSToolbarItem.Identifier {
    static let snapSort = NSToolbarItem.Identifier("snapbar.sort")
    static let snapSize = NSToolbarItem.Identifier("snapbar.size")
    static let snapSearch = NSToolbarItem.Identifier("snapbar.search")
}

/// The full library window: sidebar filters, the grid, and a toolbar with size, sort and search.
@MainActor
final class LibraryWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    static let shared = LibraryWindowController()

    let model = LibraryModel()
    private let grid: LibraryGridController
    private var openStart: Date?
    private weak var sortItem: NSMenuToolbarItem?

    private init() {
        grid = LibraryGridController(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Screenshot Library")
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)

        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: LibrarySidebar(model: model)))
        sidebar.minimumThickness = 220
        sidebar.maximumThickness = 320
        sidebar.canCollapse = true
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: grid))
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1120, height: 740))
        window.delegate = self

        let toolbar = NSToolbar(identifier: "SnapBarLibraryToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        if !window.setFrameUsingName("SnapBarLibrary") { window.center() }
        window.setFrameAutosaveName("SnapBarLibrary")

        grid.onFirstAppear = { [weak self] in
            guard let self, let start = self.openStart else { return }
            Log.info("library open ms=\(Log.ms(since: start)) items=\(self.model.visible.count) total=\(self.model.store.shots.count)")
            self.openStart = nil
        }
        model.$visible
            .sink { [weak window] visible in
                window?.subtitle = String(localized: "\(visible.count) screenshots")
            }
            .store(in: &subscriptions)
    }

    private var subscriptions = Set<AnyCancellable>()

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        openStart = Date()
        AppWindows.didOpen(window)
        window?.makeKeyAndOrderFront(nil)
        grid.focusGrid()
        if window?.isVisible == true, grid.hasAppeared, let start = openStart {
            Log.info("library open ms=\(Log.ms(since: start)) items=\(model.visible.count) total=\(model.store.shots.count) warm=true")
            openStart = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        grid.closeQuickLook()
        AppWindows.didClose(window)
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .snapSize, .snapSort, .snapSearch]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .snapSort:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: nil)
            item.label = String(localized: "Sort")
            item.toolTip = String(localized: "Sort")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            item.showsIndicator = true
            sortItem = item
            return item
        case .snapSize:
            let slider = NSSlider(value: model.settings.thumbnailSize, minValue: 120, maxValue: 320,
                                  target: self, action: #selector(sizeChanged(_:)))
            slider.numberOfTickMarks = 5
            slider.allowsTickMarkValuesOnly = true
            slider.controlSize = .small
            slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = slider
            item.label = String(localized: "Thumbnail Size")
            item.toolTip = String(localized: "Thumbnail Size")
            return item
        case .snapSearch:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField.delegate = self
            item.searchField.placeholderString = String(localized: "Search text in screenshots")
            item.preferredWidthForSearchField = 260
            return item
        default:
            return nil
        }
    }

    @objc private func sizeChanged(_ sender: NSSlider) {
        model.settings.thumbnailSize = sender.doubleValue
        grid.setThumbnailSize(sender.doubleValue)
        Log.info("library thumbnails size=\(Int(sender.doubleValue))")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let options: [(ShotSort, String)] = [
            (.newestFirst, String(localized: "Newest First")),
            (.oldestFirst, String(localized: "Oldest First")),
            (.largestFirst, String(localized: "Largest Files First")),
        ]
        for (sort, title) in options {
            let item = NSMenuItem(title: title, action: #selector(sortChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sort.rawValue
            item.state = model.query.sort == sort ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func sortChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sort = ShotSort(rawValue: raw) else { return }
        model.setSort(sort)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        model.setSearch(field.stringValue)
    }
}

#if DEBUG
extension LibraryWindowController {
    func debugFilter(_ spec: String) {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count > 1 ? parts[1] : ""
        switch parts.first ?? "" {
        case "all": model.setDateFilter(.all)
        case "today": model.setDateFilter(.today)
        case "yesterday": model.setDateFilter(.yesterday)
        case "last7": model.setDateFilter(.last7Days)
        case "last30": model.setDateFilter(.last30Days)
        case "thisMonth": model.setDateFilter(.thisMonth)
        case "custom":
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let days = value.split(separator: ",").compactMap { f.date(from: String($0)) }
            if days.count == 2 {
                model.customFrom = days[0]
                model.customTo = days[1]
                model.applyCustomRange()
            }
        case "source": if let s = ShotSource(rawValue: value) { model.toggleSource(s) }
        case "app": model.selectApp(value.isEmpty ? nil : value)
        case "fav": model.toggleFavoritesOnly()
        case "search": model.setSearch(value)
        case "sort": if let s = ShotSort(rawValue: value) { model.setSort(s) }
        case "size":
            let size = Double(value) ?? 180
            model.settings.thumbnailSize = size
            grid.setThumbnailSize(size)
        case "clear": model.clearFilters()
        default: break
        }
        Log.info("debug filter spec=\(spec) results=\(model.visible.count)")
    }

    func debugSelect(count: Int) { grid.debugSelect(count: count) }
    func debugQuickLook() { grid.toggleQuickLook() }
    func debugCopySelection() { grid.copySelection() }
    func debugContextMenu() { grid.debugDumpContextMenu() }
    func debugGrid() { grid.debugDumpGrid() }

    func debugExportSelection(to path: String) {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let written = ShotActions.exportFiles(model.selectedShots.map(\.url), to: folder)
        Log.info("action export count=\(written.count) folder=\(folder.path)")
    }

    func debugTrashSelection() {
        ShotActions.trash(model.selectedShots, confirm: false)
    }

    func debugFavoriteSelection() {
        ShotActions.toggleFavorite(model.selectedShots)
    }
}
#endif
