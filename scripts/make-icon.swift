// Draws the SnapBar app icon at 1024 px: a blue squircle with white viewfinder corners and a lens.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius: CGFloat = 185
let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.30, blue: 0.85, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let colors = [CGColor(srgbRed: 0.29, green: 0.58, blue: 1.00, alpha: 1),
              CGColor(srgbRed: 0.08, green: 0.27, blue: 0.80, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: size / 2, y: body.maxY), end: CGPoint(x: size / 2, y: body.minY), options: [])
let shine = [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray
let shineGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: shine, locations: [0, 1])!
ctx.drawLinearGradient(shineGradient, start: CGPoint(x: size / 2, y: body.maxY), end: CGPoint(x: size / 2, y: body.midY), options: [])
ctx.restoreGState()

let frame = body.insetBy(dx: 170, dy: 170)
let arm: CGFloat = 150
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(58)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let corners: [(CGPoint, CGFloat, CGFloat)] = [
    (CGPoint(x: frame.minX, y: frame.maxY), 1, -1), (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
    (CGPoint(x: frame.minX, y: frame.minY), 1, 1), (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
]
for (p, sx, sy) in corners {
    ctx.move(to: CGPoint(x: p.x, y: p.y + sy * arm))
    ctx.addLine(to: p)
    ctx.addLine(to: CGPoint(x: p.x + sx * arm, y: p.y))
    ctx.strokePath()
}
let lens = CGRect(x: size / 2 - 92, y: size / 2 - 92, width: 184, height: 184)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillEllipse(in: lens)
ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.33, blue: 0.88, alpha: 1))
ctx.fillEllipse(in: lens.insetBy(dx: 44, dy: 44))

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
