import AppKit
import Combine
import Quartz

/// The screenshot grid: native multi-select, drag out, Quick Look, context menu, pinned day headers.
@MainActor
final class LibraryGridController: NSViewController, NSCollectionViewDelegate {
    let model: LibraryModel
    var onFirstAppear: (() -> Void)?
    private(set) var hasAppeared = false

    private let collectionView = ShotCollectionView()
    private var dataSource: NSCollectionViewDiffableDataSource<String, UUID>?
    private var shotsByID: [UUID: Shot] = [:]
    private var sectionsByID: [String: ShotSection] = [:]
    private var previewURLs: [URL] = []
    private var cancellables = Set<AnyCancellable>()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptyHint = NSTextField(labelWithString: "")

    init(model: LibraryModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        collectionView.collectionViewLayout = makeLayout(size: model.settings.thumbnailSize)
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(ShotItem.self, forItemWithIdentifier: ShotItem.identifier)
        collectionView.register(SectionHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                                withIdentifier: SectionHeader.identifier)
        collectionView.delegate = self
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.controller = self
        scroll.documentView = collectionView

        emptyTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        emptyTitle.alignment = .center
        emptyHint.font = .systemFont(ofSize: 13)
        emptyHint.textColor = .secondaryLabelColor
        emptyHint.alignment = .center
        let empty = NSStackView(views: [emptyTitle, emptyHint])
        empty.orientation = .vertical
        empty.spacing = 6
        empty.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(scroll)
        container.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -48),
        ])
        view = container
        configureDataSource()
        model.$sections
            .sink { [weak self] sections in self?.apply(sections) }
            .store(in: &cancellables)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        collectionView.layoutSubtreeIfNeeded()
        if !hasAppeared {
            hasAppeared = true
            onFirstAppear?()
        }
    }

    func focusGrid() {
        view.window?.makeFirstResponder(collectionView)
    }

    // MARK: Data

    private func makeLayout(size: Double) -> NSCollectionViewFlowLayout {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = ShotItem.itemSize(for: size)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 18
        layout.sectionInset = NSEdgeInsets(top: 6, left: 22, bottom: 26, right: 22)
        layout.headerReferenceSize = NSSize(width: 100, height: 42)
        layout.sectionHeadersPinToVisibleBounds = true
        return layout
    }

    func setThumbnailSize(_ size: Double) {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = ShotItem.itemSize(for: size)
        layout.invalidateLayout()
        reconfigureVisibleItems()
    }

    private func configureDataSource() {
        let source = NSCollectionViewDiffableDataSource<String, UUID>(collectionView: collectionView) { [weak self] cv, indexPath, id in
            let item = cv.makeItem(withIdentifier: ShotItem.identifier, for: indexPath)
            if let self, let shotItem = item as? ShotItem, let shot = self.shotsByID[id] {
                shotItem.configure(shot: shot, size: self.model.settings.thumbnailSize)
            }
            return item
        }
        source.supplementaryViewProvider = { [weak self] cv, kind, indexPath in
            guard kind == NSCollectionView.elementKindSectionHeader,
                  let header = cv.makeSupplementaryView(ofKind: kind, withIdentifier: SectionHeader.identifier,
                                                        for: indexPath) as? SectionHeader,
                  let self, let snapshot = self.dataSource?.snapshot(),
                  snapshot.sectionIdentifiers.indices.contains(indexPath.section) else { return nil }
            header.configure(section: self.sectionsByID[snapshot.sectionIdentifiers[indexPath.section]])
            return header
        }
        dataSource = source
    }

    private func apply(_ sections: [ShotSection]) {
        var byID: [UUID: Shot] = [:]
        for section in sections { for shot in section.shots { byID[shot.id] = shot } }
        shotsByID = byID
        sectionsByID = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var snapshot = NSDiffableDataSourceSnapshot<String, UUID>()
        for section in sections {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.shots.map(\.id), toSection: section.id)
        }
        let animate = view.window?.isVisible == true && byID.count < 400
        dataSource?.apply(snapshot, animatingDifferences: animate)
        reconfigureVisibleItems()
        restoreSelection()
        updateEmptyState(isEmpty: sections.isEmpty)
    }

    private func reconfigureVisibleItems() {
        for case let item as ShotItem in collectionView.visibleItems() {
            if let id = item.shotID, let shot = shotsByID[id] {
                item.configure(shot: shot, size: model.settings.thumbnailSize)
            }
        }
        for case let header as SectionHeader in collectionView.visibleSupplementaryViews(ofKind: NSCollectionView.elementKindSectionHeader) {
            header.refreshCount(sectionsByID)
        }
    }

    private func restoreSelection() {
        guard let source = dataSource else { return }
        let paths = model.selection.compactMap { source.indexPath(for: $0) }
        collectionView.selectionIndexPaths = Set(paths)
    }

    private func updateEmptyState(isEmpty: Bool) {
        let libraryEmpty = model.store.shots.isEmpty
        emptyTitle.stringValue = libraryEmpty ? String(localized: "No screenshots yet") : String(localized: "Nothing matches these filters")
        emptyHint.stringValue = libraryEmpty
            ? String(localized: "Press ⇧⌘S to take your first one. It will appear here.")
            : String(localized: "Try another date or clear the search.")
        emptyTitle.superview?.isHidden = !isEmpty
    }

    private func syncSelectionToModel() {
        guard let source = dataSource else { return }
        model.selection = Set(collectionView.selectionIndexPaths.compactMap { source.itemIdentifier(for: $0) })
    }

    func shots(at paths: Set<IndexPath>) -> [Shot] {
        guard let source = dataSource else { return [] }
        return paths.sorted().compactMap { source.itemIdentifier(for: $0) }.compactMap { shotsByID[$0] }
    }

    var selectedShots: [Shot] { shots(at: collectionView.selectionIndexPaths) }

    // MARK: NSCollectionViewDelegate

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        syncSelectionToModel()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        guard let id = dataSource?.itemIdentifier(for: indexPath), let shot = shotsByID[id] else { return nil }
        return shot.url as NSURL
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
                        endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        Log.info("library drag ended operation=\(operation.rawValue) count=\(session.draggingPasteboard.pasteboardItems?.count ?? 0)")
    }

    // MARK: Actions

    func openEditor(at indexPath: IndexPath) {
        guard let id = dataSource?.itemIdentifier(for: indexPath), let shot = shotsByID[id] else { return }
        ShotActions.edit(shot)
    }

    func copySelection() {
        let shots = selectedShots
        guard !shots.isEmpty else { return }
        ShotActions.copy(shots)
    }

    func trashSelection() {
        ShotActions.trash(selectedShots)
    }

    func contextMenu() -> NSMenu? {
        let shots = selectedShots
        guard !shots.isEmpty else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String, _ handler: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, handler: handler)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        add(shots.count == 1 ? String(localized: "Copy") : String(localized: "Copy \(shots.count) Screenshots"), "doc.on.doc") { ShotActions.copy(shots) }
        if let first = shots.first {
            add(String(localized: "Edit"), "pencil.tip.crop.circle") { ShotActions.edit(first) }
            add(String(localized: "Copy Text"), "text.viewfinder") { ShotActions.copyText(first) }
        }
        add(String(localized: "Show in Finder"), "folder") { ShotActions.reveal(shots) }
        add(String(localized: "Copy Path"), "link") { ShotActions.copyPath(shots) }
        menu.addItem(.separator())
        let allFavorite = shots.allSatisfy(\.favorite)
        add(allFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
            allFavorite ? "star.slash" : "star") { ShotActions.toggleFavorite(shots) }
        add(String(localized: "Export…"), "square.and.arrow.up") { ShotActions.export(shots) }
        menu.addItem(.separator())
        add(String(localized: "Move to Trash"), "trash") { ShotActions.trash(shots) }
        return menu
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
            return
        }
        previewURLs = model.visible.map(\.url)
        guard !previewURLs.isEmpty else { return }
        let start = model.visible.firstIndex { model.selection.contains($0.id) } ?? 0
        // The panel finds its controller through the responder chain, so the grid must hold focus.
        // Assigning the source directly as well keeps it correct when the window is not key.
        view.window?.makeFirstResponder(collectionView)
        panel.makeKeyAndOrderFront(nil)
        panel.updateController()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = start
        Log.info("quicklook open index=\(start) items=\(previewURLs.count)")
    }

    func closeQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
    }

    fileprivate func beginPreview(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }
}

extension LibraryGridController: @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }
}

/// Collection view with the keyboard behaviour the library promises: Space, Return, ⌘⌫, double-click.
final class ShotCollectionView: NSCollectionView {
    weak var controller: LibraryGridController?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 49 where flags.isEmpty:
            controller?.toggleQuickLook()
        case 36, 76:
            controller?.copySelection()
        case 51 where flags.contains(.command):
            controller?.trashSelection()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            if let path = indexPathForItem(at: point) { controller?.openEditor(at: path) }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let path = indexPathForItem(at: point), !selectionIndexPaths.contains(path) {
            selectionIndexPaths = [path]
            delegate?.collectionView?(self, didSelectItemsAt: [path])
        }
        return controller?.contextMenu()
    }

    @objc func copy(_ sender: Any?) {
        controller?.copySelection()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        controller?.beginPreviewPanelControlProxy(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

extension LibraryGridController {
    func beginPreviewPanelControlProxy(_ panel: QLPreviewPanel) {
        beginPreview(panel)
    }
}

/// NSMenuItem that runs a closure, so context menus stay next to the code they call.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func run() {
        handler()
    }
}

#if DEBUG
extension LibraryGridController {
    func debugSelect(count: Int) {
        guard let source = dataSource else { return }
        let ids = Array(source.snapshot().itemIdentifiers.prefix(count))
        collectionView.selectionIndexPaths = Set(ids.compactMap { source.indexPath(for: $0) })
        syncSelectionToModel()
        Log.info("debug selected=\(ids.count)")
    }

    func debugDumpGrid() {
        let sections = collectionView.numberOfSections
        let counts = (0..<sections).map { collectionView.numberOfItems(inSection: $0) }
        let visible = collectionView.visibleItems()
        let withImage = visible.compactMap { $0 as? ShotItem }.filter { $0.debugHasImage }.count
        let firstFrame = visible.first.map { NSStringFromRect($0.view.frame) } ?? "-"
        Log.info("debug grid sections=\(sections) counts=\(counts) visible=\(visible.count) withImage=\(withImage) firstFrame=\(firstFrame) scrollSize=\(NSStringFromSize(collectionView.frame.size))")
    }

    func debugDumpContextMenu() {
        for item in contextMenu()?.items ?? [] where !item.isSeparatorItem {
            Log.info("context item title=\(item.title)")
        }
    }
}
#endif
