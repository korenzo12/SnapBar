import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// One editor window per screenshot.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [UUID: EditorWindowController] = [:]

    static func open(shot: Shot) {
        if let existing = open[shot.id] {
            AppWindows.didOpen(existing.window)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let controller = EditorWindowController(shot: shot) else {
            Log.info("editor open failed unreadable file=\(shot.fileName)")
            return
        }
        open[shot.id] = controller
        controller.present()
    }

    let shot: Shot
    let model = EditorModel()
    private let canvas: EditorCanvasView
    private let scroll = NSScrollView()

    private init?(shot: Shot) {
        guard let image = ImageTools.loadCGImage(url: shot.url) else { return nil }
        self.shot = shot
        canvas = EditorCanvasView(image: image, pixelsPerPoint: EditorWindowController.pixelsPerPoint(url: shot.url), model: model)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = shot.fileName
        window.subtitle = String(localized: "editor.subtitle", defaultValue: "Editing")
        window.minSize = NSSize(width: 820, height: 520)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = false
        super.init(window: window)
        window.delegate = self

        scroll.contentView = CenteringClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 4
        scroll.backgroundColor = .windowBackgroundColor
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let actions = EditorActions(
            undo: { [weak self] in self?.canvas.undo(nil) },
            redo: { [weak self] in self?.canvas.redo(nil) },
            zoomIn: { [weak self] in self?.canvas.zoomIn(nil) },
            zoomOut: { [weak self] in self?.canvas.zoomOut(nil) },
            zoomFit: { [weak self] in self?.canvas.zoomToFit(nil) },
            resetCrop: { [weak self] in self?.canvas.resetCrop(nil) },
            copy: { [weak self] in self?.copyResult() },
            save: { [weak self] in self?.saveOverOriginal() },
            saveAs: { [weak self] in self?.export(type: .png) },
            exportJPEG: { [weak self] in self?.export(type: .jpeg) }
        )
        canvas.onCopy = { [weak self] in self?.copyResult() }
        canvas.onSave = { [weak self] in self?.saveOverOriginal() }
        canvas.onSaveAs = { [weak self] in self?.export(type: .png) }

        let bar = NSHostingView(rootView: EditorToolbar(model: model, actions: actions))
        bar.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(bar)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 50),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Retina screenshots are stored at 144 DPI, so two pixels make one point.
    static func pixelsPerPoint(url: URL) -> CGFloat {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 else { return 1 }
        return CGFloat(dpi / 72)
    }

    private func present() {
        AppWindows.didOpen(window)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.canvas.zoomToFit(nil) }
        }
        Log.info("editor open id=\(shot.id.uuidString) size=\(canvas.image.width)x\(canvas.image.height)")
    }

    // MARK: Output

    private func copyResult() {
        guard let image = canvas.renderedImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        let item = NSPasteboardItem()
        if let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pasteboard.writeObjects([item])
        Log.info("editor copy size=\(image.width)x\(image.height)")
    }

    private func saveOverOriginal() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Replace the original screenshot?")
        alert.informativeText = String(localized: "The marks become part of the picture. Use Save As to keep the original.")
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let image = canvas.renderedImage() else { return }
        let type: UTType = ["jpg", "jpeg"].contains(shot.url.pathExtension.lowercased()) ? .jpeg : .png
        let ok = ImageTools.write(image, to: shot.url, type: type)
        if ok {
            ThumbnailCache.shared.invalidate(shot.id)
            let info = ImageTools.info(url: shot.url)
            ShotStore.shared.update(shot.id) {
                $0.pixelWidth = info?.width ?? $0.pixelWidth
                $0.pixelHeight = info?.height ?? $0.pixelHeight
                $0.fileSize = info?.fileSize ?? $0.fileSize
            }
            canvas.markSaved()
        }
        Log.info("editor save ok=\(ok) file=\(shot.fileName) size=\(image.width)x\(image.height)")
    }

    private func export(type: UTType) {
        guard let image = canvas.renderedImage() else { return }
        let panel = NSSavePanel()
        let base = (shot.fileName as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + (type == .jpeg ? ".jpg" : " " + String(localized: "edited") + ".png")
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                let ok = ImageTools.write(image, to: url, type: type, quality: 0.92)
                Log.info("editor export type=\(type == .jpeg ? "jpeg" : "png") ok=\(ok) file=\(url.lastPathComponent)")
            }
        }
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.dirty else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Close without saving?")
        alert.informativeText = String(localized: "Your marks will be lost. Copy or save first to keep them.")
        alert.addButton(withTitle: String(localized: "Close"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        EditorWindowController.open[shot.id] = nil
        AppWindows.didClose(window)
        Log.info("editor closed id=\(shot.id.uuidString)")
    }
}

struct EditorActions {
    let undo: () -> Void
    let redo: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let zoomFit: () -> Void
    let resetCrop: () -> Void
    let copy: () -> Void
    let save: () -> Void
    let saveAs: () -> Void
    let exportJPEG: () -> Void
}

struct EditorToolbar: View {
    static let widthNames: [LocalizedStringKey] = ["Thin", "Medium", "Thick"]
    @ObservedObject var model: EditorModel
    let actions: EditorActions

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        model.tool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 26)
                            .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.tool == tool ? Color.accentColor : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: "\(tool.title)  (\(tool.key.uppercased()))"))
                    .accessibilityLabel(Text(verbatim: tool.title))
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))

            HStack(spacing: 6) {
                ForEach(RGBA.palette.indices, id: \.self) { index in
                    Button {
                        model.colorIndex = index
                    } label: {
                        Circle()
                            .fill(Color(nsColor: RGBA.palette[index].nsColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                            .padding(3)
                            .overlay(Circle().strokeBorder(model.colorIndex == index ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        model.widthIndex = index
                    } label: {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 16, height: [2.0, 4.0, 7.0][index])
                            .frame(width: 28, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.widthIndex == index ? Color.accentColor.opacity(0.2) : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(EditorToolbar.widthNames[index]))
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button(action: actions.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).help(Text("Undo"))
                Button(action: actions.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).help(Text("Redo"))
            }
            .buttonStyle(.borderless)

            HStack(spacing: 4) {
                Button(action: actions.zoomOut) { Image(systemName: "minus.magnifyingglass") }.help(Text("Zoom Out"))
                Button(action: actions.zoomFit) {
                    Text(verbatim: "\(model.zoomPercent)%").monospacedDigit().frame(minWidth: 44)
                }
                .help(Text("Zoom to Fit"))
                Button(action: actions.zoomIn) { Image(systemName: "plus.magnifyingglass") }.help(Text("Zoom In"))
            }
            .buttonStyle(.borderless)

            if model.hasCrop {
                Button("Reset Crop", action: actions.resetCrop)
            }

            Menu {
                Button("Save As PNG…", action: actions.saveAs)
                Button("Export as JPEG…", action: actions.exportJPEG)
            } label: {
                Text("Export")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("Save", action: actions.save)
            Button(action: actions.copy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

#if DEBUG
extension EditorWindowController {
    static var debugCurrent: EditorWindowController? {
        open.values.first { $0.window?.isKeyWindow == true } ?? open.values.first
    }

    /// One mark of every tool, placed relative to the picture, for the P5 proof screenshot.
    func debugDemo(text: String) {
        let w = CGFloat(canvas.image.width)
        let h = CGFloat(canvas.image.height)
        let px = canvas.pixelsPerPoint
        let red = RGBA.palette[0]
        let blue = RGBA.palette[4]
        let yellow = RGBA.palette[2]
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        let pen = stride(from: 0.0, through: 1.0, by: 0.05).map { t in p(0.62 + t * 0.2, 0.80 + (Int(t * 20) % 2 == 0 ? 0 : 0.03)) }
        let marks: [Annotation] = [
            Annotation(kind: .arrow(from: p(0.18, 0.70), to: p(0.40, 0.52)), color: red, lineWidth: 4 * px),
            Annotation(kind: .line(from: p(0.06, 0.93), to: p(0.40, 0.93)), color: blue, lineWidth: 2 * px),
            Annotation(kind: .rectangle(CGRect(x: 0.42 * w, y: 0.40 * h, width: 0.16 * w, height: 0.24 * h)), color: red, lineWidth: 4 * px),
            Annotation(kind: .ellipse(CGRect(x: 0.66 * w, y: 0.20 * h, width: 0.22 * w, height: 0.16 * h)), color: blue, lineWidth: 4 * px),
            Annotation(kind: .pen(pen), color: RGBA.palette[5], lineWidth: 4 * px),
            Annotation(kind: .marker([p(0.08, 0.14), p(0.36, 0.14)]), color: yellow, lineWidth: 4 * px),
            Annotation(kind: .text(text, at: p(0.30, 0.74), fontSize: 22 * px, alignRight: true), color: red, lineWidth: 4 * px),
            Annotation(kind: .blur(CGRect(x: 0.06 * w, y: 0.24 * h, width: 0.26 * w, height: 0.12 * h)), color: red, lineWidth: 4 * px),
            Annotation(kind: .step(1, at: p(0.44, 0.38)), color: red, lineWidth: 4 * px),
            Annotation(kind: .step(2, at: p(0.70, 0.18)), color: blue, lineWidth: 4 * px),
        ]
        canvas.debugApply(marks)
    }

    func debugCrop(_ fraction: CGRect) {
        let w = CGFloat(canvas.image.width)
        let h = CGFloat(canvas.image.height)
        canvas.debugApply([], crop: CGRect(x: fraction.minX * w, y: fraction.minY * h, width: fraction.width * w, height: fraction.height * h))
    }

    func debugZoom(_ value: Double) { canvas.setZoom(CGFloat(value)) }
    func debugTool(_ key: String) { if let tool = EditorTool.tool(forKey: key) { model.tool = tool } }
    func debugCopy() { copyResult() }

    func debugExport(to path: String) {
        guard let image = canvas.renderedImage() else { return }
        let url = URL(fileURLWithPath: path)
        let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
        let ok = ImageTools.write(image, to: url, type: type, quality: 0.92)
        Log.info("editor export type=\(type == .jpeg ? "jpeg" : "png") ok=\(ok) file=\(url.lastPathComponent) size=\(image.width)x\(image.height)")
    }

    func debugUndoRedo() {
        let undone = canvas.debugUndoAll()
        let emptyAfterUndo = canvas.state.annotations.isEmpty && canvas.state.crop == nil
        let redone = canvas.debugRedoAll()
        Log.info("editor undoAll=\(undone) emptyAfterUndo=\(emptyAfterUndo) redoAll=\(redone) marks=\(canvas.state.annotations.count)")
    }
}
#endif
