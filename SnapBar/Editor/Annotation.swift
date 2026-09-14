import AppKit

struct RGBA: Equatable, Hashable, Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat = 1

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func with(alpha: CGFloat) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// Eight colours: red, orange, yellow, green, blue, purple, black, white.
    static let palette: [RGBA] = [
        RGBA(r: 1.00, g: 0.23, b: 0.19), RGBA(r: 1.00, g: 0.58, b: 0.00),
        RGBA(r: 1.00, g: 0.80, b: 0.00), RGBA(r: 0.20, g: 0.78, b: 0.35),
        RGBA(r: 0.00, g: 0.48, b: 1.00), RGBA(r: 0.69, g: 0.32, b: 0.87),
        RGBA(r: 0.11, g: 0.11, b: 0.12), RGBA(r: 1.00, g: 1.00, b: 1.00),
    ]
}

enum EditorTool: String, CaseIterable, Identifiable, Sendable {
    case arrow, line, rectangle, ellipse, pen, marker, text, blur, step, crop
    var id: String { rawValue }

    /// Single-key shortcuts, shown in the Tools menu.
    var key: String {
        switch self {
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .pen: return "p"
        case .marker: return "m"
        case .text: return "t"
        case .blur: return "b"
        case .step: return "n"
        case .crop: return "c"
        }
    }

    static func tool(forKey key: String) -> EditorTool? {
        allCases.first { $0.key == key.lowercased() }
    }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .text: return "textformat"
        case .blur: return "square.grid.3x3.fill"
        case .step: return "1.circle"
        case .crop: return "crop"
        }
    }

    var title: String {
        switch self {
        case .arrow: return String(localized: "Arrow")
        case .line: return String(localized: "Line")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .pen: return String(localized: "Pen")
        case .marker: return String(localized: "Highlighter")
        case .text: return String(localized: "Text")
        case .blur: return String(localized: "Blur")
        case .step: return String(localized: "Step Number")
        case .crop: return String(localized: "Crop")
        }
    }
}

/// One mark on the picture, in image pixels with a top-left origin.
struct Annotation: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case pen([CGPoint])
        case marker([CGPoint])
        case text(String, at: CGPoint, fontSize: CGFloat, alignRight: Bool)
        case blur(CGRect)
        case step(Int, at: CGPoint)
    }

    let id: UUID
    var kind: Kind
    var color: RGBA
    var lineWidth: CGFloat

    init(id: UUID = UUID(), kind: Kind, color: RGBA, lineWidth: CGFloat) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }
}

struct EditorState: Equatable, Sendable {
    var annotations: [Annotation] = []
    var crop: CGRect?

    var nextStepNumber: Int {
        let steps = annotations.compactMap { a -> Int? in
            if case .step(let n, _) = a.kind { return n }
            return nil
        }
        return (steps.max() ?? 0) + 1
    }
}

/// Unlimited undo and redo over whole editor states.
struct EditHistory<State: Equatable> {
    private(set) var current: State
    private var past: [State] = []
    private var future: [State] = []

    init(_ initial: State) {
        current = initial
    }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var undoCount: Int { past.count }

    mutating func commit(_ next: State) {
        guard next != current else { return }
        past.append(current)
        current = next
        future.removeAll()
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = past.popLast() else { return false }
        future.append(current)
        current = previous
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append(current)
        current = next
        return true
    }
}
