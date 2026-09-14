import AppKit

enum AnnotationDrawing {
    /// Draws a CGImage into `rect` of a context whose coordinates have a top-left origin.
    static func drawImageTopLeft(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Vector marks. The context is in image pixels, top-left origin. Blur is raster and drawn elsewhere.
    static func draw(_ annotation: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setFillColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        switch annotation.kind {
        case .line(let from, let to):
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, width: annotation.lineWidth, ctx)
        case .rectangle(let rect):
            let r = rect.standardized
            let radius = min(annotation.lineWidth, r.width / 2, r.height / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        case .ellipse(let rect):
            ctx.strokeEllipse(in: rect.standardized)
        case .pen(let points):
            stroke(points, ctx)
        case .marker(let points):
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(annotation.color.with(alpha: 0.42).cgColor)
            ctx.setLineWidth(annotation.lineWidth * 4)
            stroke(points, ctx)
        case .text(let string, let at, let fontSize, let alignRight):
            drawText(string, at: at, fontSize: fontSize, alignRight: alignRight, color: annotation.color, ctx)
        case .step(let number, let at):
            drawStep(number, at: at, radius: max(annotation.lineWidth * 3.2, 16), color: annotation.color, ctx)
        case .blur:
            break
        }
    }

    private static func stroke(_ points: [CGPoint], _ ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.move(to: first)
        if points.count == 1 { ctx.addLine(to: first) }
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, _ ctx: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1 else { return }
        let ux = dx / length
        let uy = dy / length
        let head = min(max(width * 3.6, 14), length * 0.6)
        let half = head * 0.55
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        ctx.move(to: from)
        ctx.addLine(to: CGPoint(x: to.x - ux * head * 0.6, y: to.y - uy * head * 0.6))
        ctx.strokePath()
        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        ctx.closePath()
        ctx.fillPath()
    }

    static func textAttributes(fontSize: CGFloat, color: RGBA) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .natural
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = fontSize * 0.12
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.04)
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color.nsColor,
            .paragraphStyle: paragraph,
            .shadow: shadow,
        ]
    }

    static func textSize(_ string: String, fontSize: CGFloat) -> CGSize {
        NSAttributedString(string: string, attributes: textAttributes(fontSize: fontSize, color: RGBA.palette[0])).size()
    }

    private static func drawText(_ string: String, at: CGPoint, fontSize: CGFloat, alignRight: Bool, color: RGBA, _ ctx: CGContext) {
        let attributed = NSAttributedString(string: string, attributes: textAttributes(fontSize: fontSize, color: color))
        let size = attributed.size()
        let origin = CGPoint(x: alignRight ? at.x - size.width : at.x, y: at.y)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        attributed.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawStep(_ number: Int, at: CGPoint, radius: CGFloat, color: RGBA, _ ctx: CGContext) {
        let circle = CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)
        ctx.setShadow(offset: CGSize(width: 0, height: radius * 0.08), blur: radius * 0.3,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(max(2, radius * 0.12))
        ctx.strokeEllipse(in: circle.insetBy(dx: radius * 0.06, dy: radius * 0.06))
        let label = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: radius * 1.05, weight: .heavy),
            .foregroundColor: color == RGBA.palette[7] ? NSColor.black : NSColor.white,
        ])
        let size = label.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        label.draw(at: CGPoint(x: at.x - size.width / 2, y: at.y - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum Pixelate {
    /// A pixelated copy of `rect` (image pixels, top-left origin). Text under it becomes unreadable.
    static func region(of image: CGImage, rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = rect.standardized.integral.intersection(bounds)
        guard r.width >= 2, r.height >= 2, let piece = image.cropping(to: r) else { return nil }
        let block = max(8, Int(min(r.width, r.height) / 9))
        let small = CGSize(width: max(1, Int(r.width) / block), height: max(1, Int(r.height) / block))
        guard let tiny = ImageTools.resize(piece, to: small),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(r.width), height: Int(r.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(tiny, in: CGRect(origin: .zero, size: r.size))
        return ctx.makeImage()
    }
}

/// Flattens the picture and its marks at the picture's own pixel size, then applies the crop.
enum AnnotationRenderer {
    static func render(image: CGImage, state: EditorState) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var area = full
        if let crop = state.crop {
            let clipped = crop.standardized.integral.intersection(full)
            if clipped.width >= 1, clipped.height >= 1 { area = clipped }
        }
        let bitmap = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let preferred = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let space = preferred ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: bitmap) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: area.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -area.minX, y: -area.minY)
        AnnotationDrawing.drawImageTopLeft(image, in: full, ctx)
        for annotation in state.annotations {
            if case .blur(let rect) = annotation.kind, let pixelated = Pixelate.region(of: image, rect: rect) {
                let r = rect.standardized.integral.intersection(full)
                AnnotationDrawing.drawImageTopLeft(pixelated, in: r, ctx)
            }
        }
        for annotation in state.annotations {
            AnnotationDrawing.draw(annotation, in: ctx)
        }
        return ctx.makeImage()
    }
}
