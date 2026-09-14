import AppKit

/// Downsampled thumbnails, in memory and as small JPEGs on disk, generated off the main thread.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "co.il.ckdigital360.snapbar.thumbs", qos: .userInitiated, attributes: .concurrent)
    let directory: URL

    init(directory: URL = ShotStore.supportDirectory.appendingPathComponent("thumbs", isDirectory: true)) {
        self.directory = directory
        memory.countLimit = 800
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 256 or 512 pixels, so the cache holds two sizes at most.
    static func bucket(forPoints points: CGFloat) -> Int { points * 2 > 300 ? 512 : 256 }

    private func key(_ id: UUID, _ size: Int) -> NSString { "\(id.uuidString)-\(size)" as NSString }

    func cached(_ id: UUID, size: Int) -> NSImage? { memory.object(forKey: key(id, size)) }

    func thumbnail(for shot: Shot, size: Int, completion: @escaping @MainActor (NSImage?) -> Void) {
        let cacheKey = key(shot.id, size)
        if let hit = memory.object(forKey: cacheKey) {
            MainActor.assumeIsolated { completion(hit) }
            return
        }
        let diskURL = directory.appendingPathComponent("\(shot.id.uuidString)-\(size).jpg")
        let sourceURL = shot.url
        queue.async { [memory] in
            var image: NSImage?
            if let data = try? Data(contentsOf: diskURL), let disk = NSImage(data: data) {
                image = disk
            } else if let cg = ImageTools.thumbnail(url: sourceURL, maxPixel: size) {
                ImageTools.write(cg, to: diskURL, type: .jpeg, quality: 0.82)
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            if let image { memory.setObject(image, forKey: cacheKey) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(image) }
            }
        }
    }

    /// Drops both sizes of one shot's thumbnail after its file changed.
    func invalidate(_ id: UUID) {
        for size in [256, 512] {
            memory.removeObject(forKey: key(id, size))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString)-\(size).jpg"))
        }
    }

    func removeAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
