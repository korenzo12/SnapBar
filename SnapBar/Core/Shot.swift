import Foundation

enum ShotSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case snapbar, native, imported
    var id: String { rawValue }
}

/// One screenshot in the library index. The image itself stays a normal file on disk.
struct Shot: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var path: String
    var createdAt: Date
    var source: ShotSource
    var appName: String?
    var appBundleID: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSize: Int64
    var ocrText: String?
    var favorite: Bool

    init(id: UUID = UUID(), path: String, createdAt: Date, source: ShotSource,
         appName: String? = nil, appBundleID: String? = nil,
         pixelWidth: Int = 0, pixelHeight: Int = 0, fileSize: Int64 = 0,
         ocrText: String? = nil, favorite: Bool = false) {
        self.id = id
        self.path = path
        self.createdAt = createdAt
        self.source = source
        self.appName = appName
        self.appBundleID = appBundleID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSize = fileSize
        self.ocrText = ocrText
        self.favorite = favorite
    }

    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { url.lastPathComponent }

    enum CodingKeys: String, CodingKey {
        case id, path, createdAt, source, appName, appBundleID
        case pixelWidth, pixelHeight, fileSize, ocrText, favorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = (try? c.decode(ShotSource.self, forKey: .source)) ?? .snapbar
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID)
        pixelWidth = try c.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 0
        pixelHeight = try c.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 0
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
    }
}
