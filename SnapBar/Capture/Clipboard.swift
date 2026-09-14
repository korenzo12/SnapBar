import AppKit

/// Writes screenshots so they paste everywhere: PNG bytes for chat and mail, a file URL for Finder,
/// and TIFF produced lazily only if an older app asks for it.
@MainActor
enum Clipboard {
    private static var tiffProvider: LazyTIFFProvider?

    @discardableResult
    static func write(fileURL: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if fileURL.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: fileURL) {
            item.setData(data, forType: .png)
        }
        let provider = LazyTIFFProvider(url: fileURL)
        item.setDataProvider(provider, forTypes: [.tiff])
        tiffProvider = provider
        item.setString(fileURL.absoluteString, forType: .fileURL)
        return pasteboard.writeObjects([item])
    }

    @discardableResult
    static func write(fileURLs: [URL]) -> Bool {
        guard fileURLs.count > 1 else { return fileURLs.first.map { write(fileURL: $0) } ?? false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    @discardableResult
    static func write(image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    @discardableResult
    static func write(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

final class LazyTIFFProvider: NSObject, NSPasteboardItemDataProvider {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff, let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation else { return }
        item.setData(tiff, forType: .tiff)
    }
}
