import AppKit
import Combine

@MainActor
final class EditorModel: ObservableObject {
    @Published var tool: EditorTool = .arrow { didSet { Log.info("editor tool=\(tool.rawValue)") } }
    @Published var colorIndex = 0
    @Published var widthIndex = 1
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoomPercent = 100
    @Published var hasCrop = false
    @Published var dirty = false

    static let widthPoints: [CGFloat] = [2, 4, 8]
    static let textPoints: [CGFloat] = [16, 22, 32]

    var color: RGBA { RGBA.palette[colorIndex] }
}

/// The drawing surface. Flipped, so view points map straight onto top-left image pixels.
@MainActor
final class EditorCanvasView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    let image: CGImage
    let pixelsPerPoint: CGFloat
    let model: EditorModel
    private(set) var history = EditHistory(EditorState())
    private var savedState = EditorState()
    private var draft: Annotation?
    private var draftCrop: CGRect?
    private var dragStart: CGPoint?
    private var textField: NSTextField?
    private var textAnchor: CGPoint = .zero
    private var blurCache: [UUID: CGImage] = [:]

    init(image: CGImage, pixelsPerPoint: CGFloat, model: EditorModel) {
        self.image = image
        self.pixelsPerPoint = max(pixelsPerPoint, 1)
        self.model = model
        let size = NSSize(width: CGFloat(image.width) / self.pixelsPerPoint, height: CGFloat(image.height) / self.pixelsPerPoint)
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var state: EditorState { history.current }
    private var scale: CGFloat { bounds.width / CGFloat(image.width) }
    private var strokePixels: CGFloat { EditorModel.widthPoints[model.widthIndex] * pixelsPerPoint }
    private var textPixels: CGFloat { EditorModel.textPoints[model.widthIndex] * pixelsPerPoint }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let x = min(max(p.x / scale, 0), CGFloat(image.width))
        let y = min(max(p.y / scale, 0), CGFloat(image.height))
        return CGPoint(x: x, y: y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high
        AnnotationDrawing.drawImageTopLeft(image, in: full, ctx)
        let shown = state.annotations + (draft.map { [$0] } ?? [])
        for annotation in shown {
            guard case .blur(let rect) = annotation.kind else { continue }
            let pixelated: CGImage?
            if let cached = blurCache[annotation.id], annotation.id != draft?.id {
                pixelated = cached
            } else {
                pixelated = Pixelate.region(of: image, rect: rect)
                if annotation.id != draft?.id, let pixelated { blurCache[annotation.id] = pixelated }
            }
            if let pixelated {
                AnnotationDrawing.drawImageTopLeft(pixelated, in: rect.standardized.integral.intersection(full), ctx)
            }
        }
        for annotation in shown { AnnotationDrawing.draw(annotation, in: ctx) }
        if let crop = draftCrop ?? state.crop {
            drawCropOverlay(crop.standardized, full: full, ctx)
        }
        ctx.restoreGState()
    }

    private func drawCropOverlay(_ crop: CGRect, full: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        let path = CGMutablePath()
        path.addRect(full)
        path.addRect(crop)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5 / scale)
        ctx.setLineDash(phase: 0, lengths: [6 / scale, 4 / scale])
        ctx.stroke(crop)
        ctx.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if textField != nil { commitText() }
        let p = imagePoint(event)
        dragStart = p
        let color = model.color
        switch model.tool {
        case .arrow: draft = Annotation(kind: .arrow(from: p, to: p), color: color, lineWidth: strokePixels)
        case .line: draft = Annotation(kind: .line(from: p, to: p), color: color, lineWidth: strokePixels)
        case .rectangle: draft = Annotation(kind: .rectangle(CGRect(origin: p, size: .zero)), color: color, lineWidth: strokePixels)
        case .ellipse: draft = Annotation(kind: .ellipse(CGRect(origin: p, size: .zero)), color: color, lineWidth: strokePixels)
        case .pen: draft = Annotation(kind: .pen([p]), color: color, lineWidth: strokePixels)
        case .marker: draft = Annotation(kind: .marker([p]), color: color, lineWidth: strokePixels)
        case .blur: draft = Annotation(kind: .blur(CGRect(origin: p, size: .zero)), color: color, lineWidth: strokePixels)
        case .crop: draftCrop = CGRect(origin: p, size: .zero)
        case .step:
            commit(Annotation(kind: .step(state.nextStepNumber, at: p), color: color, lineWidth: strokePixels))
            dragStart = nil
        case .text:
            beginText(at: p)
            dragStart = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var p = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)
        if shift { p = constrained(from: start, to: p) }
        let rect = CGRect(x: start.x, y: start.y, width: p.x - start.x, height: p.y - start.y)
        if model.tool == .crop {
            draftCrop = rect
        } else if var d = draft {
            switch d.kind {
            case .arrow: d.kind = .arrow(from: start, to: p)
            case .line: d.kind = .line(from: start, to: p)
            case .rectangle: d.kind = .rectangle(rect)
            case .ellipse: d.kind = .ellipse(rect)
            case .blur: d.kind = .blur(rect)
            case .pen(let points): d.kind = .pen(points + [p])
            case .marker(let points): d.kind = .marker(points + [p])
            default: break
            }
            draft = d
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            needsDisplay = true
        }
        if model.tool == .crop, let crop = draftCrop?.standardized {
            draftCrop = nil
            if crop.width > 8, crop.height > 8 {
                var next = state
                next.crop = crop
                apply(next, log: "crop \(Int(crop.width))x\(Int(crop.height))")
            }
            return
        }
        guard let d = draft else { return }
        draft = nil
        if isMeaningful(d) { commit(d) }
    }

    private func constrained(from start: CGPoint, to p: CGPoint) -> CGPoint {
        let dx = p.x - start.x
        let dy = p.y - start.y
        switch model.tool {
        case .rectangle, .ellipse, .crop, .blur:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        default:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = (dx * dx + dy * dy).squareRoot()
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
    }

    private func isMeaningful(_ a: Annotation) -> Bool {
        switch a.kind {
        case .arrow(let f, let t), .line(let f, let t): return hypot(t.x - f.x, t.y - f.y) > 4
        case .rectangle(let r), .ellipse(let r), .blur(let r): return abs(r.width) > 4 && abs(r.height) > 4
        case .pen(let pts), .marker(let pts): return !pts.isEmpty
        default: return true
        }
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        let alignRight = NSApp.userInterfaceLayoutDirection == .rightToLeft
        textAnchor = p
        let fontPoints = textPixels * scale
        let width: CGFloat = 340
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontPoints, weight: .bold)
        field.textColor = model.color.nsColor
        field.alignment = alignRight ? .right : .left
        field.placeholderString = String(localized: "Type here")
        field.delegate = self
        let viewPoint = CGPoint(x: p.x * scale, y: p.y * scale)
        field.frame = NSRect(x: alignRight ? viewPoint.x - width : viewPoint.x, y: viewPoint.y, width: width, height: fontPoints * 1.4)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let alignRight = field.alignment == .right
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !text.isEmpty else { return }
        commit(Annotation(kind: .text(text, at: textAnchor, fontSize: textPixels, alignRight: alignRight),
                          color: model.color, lineWidth: strokePixels))
    }

    // MARK: History

    private func commit(_ annotation: Annotation) {
        var next = state
        next.annotations.append(annotation)
        apply(next, log: "commit kind=\(kindName(annotation.kind)) count=\(next.annotations.count)")
    }

    private func apply(_ next: EditorState, log: String) {
        history.commit(next)
        Log.info("editor \(log)")
        syncModel()
    }

    private func syncModel() {
        model.canUndo = history.canUndo
        model.canRedo = history.canRedo
        model.hasCrop = state.crop != nil
        model.dirty = state != savedState
        needsDisplay = true
    }

    func markSaved() {
        savedState = state
        syncModel()
    }

    private func kindName(_ kind: Annotation.Kind) -> String {
        switch kind {
        case .arrow: return "arrow"
        case .line: return "line"
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .pen: return "pen"
        case .marker: return "marker"
        case .text: return "text"
        case .blur: return "blur"
        case .step: return "step"
        }
    }

    @objc func undo(_ sender: Any?) {
        if history.undo() { Log.info("editor undo remaining=\(history.undoCount)") }
        syncModel()
    }

    @objc func redo(_ sender: Any?) {
        if history.redo() { Log.info("editor redo") }
        syncModel()
    }

    @objc func resetCrop(_ sender: Any?) {
        var next = state
        next.crop = nil
        apply(next, log: "crop reset")
    }

    // MARK: Keyboard and menus

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.subtracting(.shift).isEmpty, let chars = event.charactersIgnoringModifiers,
           let tool = EditorTool.tool(forKey: chars) {
            model.tool = tool
            return
        }
        if event.keyCode == 53 {
            draft = nil
            draftCrop = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    @objc func selectTool(_ sender: NSMenuItem) {
        guard EditorTool.allCases.indices.contains(sender.tag) else { return }
        model.tool = EditorTool.allCases[sender.tag]
    }

    @objc func copy(_ sender: Any?) {
        onCopy?()
    }

    @objc func saveDocument(_ sender: Any?) {
        onSave?()
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        onSaveAs?()
    }

    @objc func zoomIn(_ sender: Any?) { setZoom((enclosingScrollView?.magnification ?? 1) * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom((enclosingScrollView?.magnification ?? 1) / 1.25) }
    @objc func zoomActual(_ sender: Any?) { setZoom(1) }

    @objc func zoomToFit(_ sender: Any?) {
        guard let scroll = enclosingScrollView else { return }
        let available = scroll.contentView.bounds.size
        let visible = NSSize(width: available.width * scroll.magnification, height: available.height * scroll.magnification)
        let fit = min((visible.width - 40) / bounds.width, (visible.height - 40) / bounds.height)
        setZoom(min(1, fit))
    }

    func setZoom(_ value: CGFloat) {
        guard let scroll = enclosingScrollView else { return }
        let clamped = min(max(value, 0.25), 4)
        scroll.magnification = clamped
        model.zoomPercent = Int((clamped * 100).rounded())
        Log.info("editor zoom=\(model.zoomPercent)%")
    }

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)): return history.canUndo
        case #selector(redo(_:)): return history.canRedo
        case #selector(selectTool(_:)):
            menuItem.state = EditorTool.allCases.firstIndex(of: model.tool) == menuItem.tag ? .on : .off
            return true
        default: return true
        }
    }

    func renderedImage() -> CGImage? {
        AnnotationRenderer.render(image: image, state: state)
    }
}

/// Keeps a picture smaller than the window centred instead of pinned to a corner.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

#if DEBUG
extension EditorCanvasView {
    func debugApply(_ annotations: [Annotation], crop: CGRect? = nil) {
        var next = state
        next.annotations += annotations
        if let crop { next.crop = crop }
        apply(next, log: "debug apply count=\(next.annotations.count)")
    }

    func debugUndoAll() -> Int {
        var n = 0
        while history.canUndo {
            undo(nil)
            n += 1
        }
        return n
    }

    func debugRedoAll() -> Int {
        var n = 0
        while history.canRedo {
            redo(nil)
            n += 1
        }
        return n
    }
}
#endif
