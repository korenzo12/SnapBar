// Renders a realistic 2x "app window" screenshot with readable text, for tests and proofs.
//   swift scripts/make-sample.swift out.png "Title" 0.6
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "sample.png"
let title = args.count > 2 ? args[2] : "Sales Dashboard"
let hue = args.count > 3 ? (Double(args[3]) ?? 0.6) : 0.6
let width = 2400, height = 1500
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(height))
ctx.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
let accent = NSColor(calibratedHue: hue, saturation: 0.62, brightness: 0.92, alpha: 1)
NSColor(calibratedWhite: 0.955, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 2280, height: 1380), xRadius: 28, yRadius: 28).fill()
NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 2280, height: 90), xRadius: 28, yRadius: 28).fill()
for (i, c) in [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen].enumerated() {
    c.setFill()
    NSBezierPath(ovalIn: NSRect(x: 100 + i * 50, y: 92, width: 26, height: 26)).fill()
}
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .black) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: NSPoint(x: x, y: y))
}
text(title, 140, 200, 76, .bold)
text("Updated 10 Sep 2026  ·  INVOICE 4821  ·  example.com", 140, 300, 34, .regular, .darkGray)
let cards = [("Users", "12,480"), ("Leads", "318"), ("Conversion", "2.5%")]
for (i, card) in cards.enumerated() {
    let x = CGFloat(140 + i * 700)
    accent.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 380, width: 640, height: 220), xRadius: 22, yRadius: 22).fill()
    text(card.0, x + 40, 410, 36, .medium, .darkGray)
    text(card.1, x + 40, 470, 84, .bold)
}
let heights: [CGFloat] = [0.42, 0.55, 0.48, 0.70, 0.31, 0.62, 0.80, 0.74]
for (i, h) in heights.enumerated() {
    (i == 4 ? NSColor.systemRed : accent).setFill()
    let barHeight = 620 * h
    NSBezierPath(roundedRect: NSRect(x: CGFloat(160 + i * 260), y: 1340 - barHeight, width: 170, height: barHeight), xRadius: 10, yRadius: 10).fill()
}
text("סיכום שבועי: עלייה של 12% בלידים", 1300, 660, 40, .semibold, .darkGray)
NSGraphicsContext.current = nil
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
