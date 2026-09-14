import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ImageInfo: Sendable {
    let width: Int
    let height: Int
    let fileSize: Int64
}

enum ImageTools {
    static func info(url: URL) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ImageInfo(width: width, height: height, fileSize: Int64(size))
    }

    static func loadCGImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// True when the picture is one flat colour. That is what a capture without Screen Recording permission yields.
    static func isBlank(_ image: CGImage, tolerance: Int = 6) -> Bool {
        let side = 32
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var low: [Int] = [255, 255, 255]
        var high: [Int] = [0, 0, 0]
        for i in 0..<(side * side) {
            for c in 0..<3 {
                let v = Int(pixels[i * 4 + c])
                low[c] = min(low[c], v)
                high[c] = max(high[c], v)
            }
        }
        return (0..<3).allSatisfy { high[$0] - low[$0] <= tolerance }
    }

    /// Rewrites the file at 1/scale of its pixel size (2 on Retina gives a 1x image).
    @discardableResult
    static func downscale(url: URL, by scale: CGFloat) -> CGSize? {
        guard scale > 1, let image = loadCGImage(url: url) else { return nil }
        let size = CGSize(width: (CGFloat(image.width) / scale).rounded(), height: (CGFloat(image.height) / scale).rounded())
        guard let scaled = resize(image, to: size), write(scaled, to: url, type: .png) else { return nil }
        return size
    }

    static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return false }
        let props: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
