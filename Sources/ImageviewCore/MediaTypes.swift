import Foundation

public enum MediaKind: String, Sendable {
    case image
    case animation
    case document
    case raw
}

public struct MediaItem: Identifiable, Hashable, Sendable {
    public typealias ID = String

    public let id: ID
    public let url: URL
    public let resourceIdentifier: String
    public let fileSize: Int64?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let finderLabel: Int?
    public let finderOrder: Int

    public init(
        url: URL,
        resourceIdentifier: String? = nil,
        fileSize: Int64? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        finderLabel: Int? = nil,
        finderOrder: Int = 0
    ) {
        let resolvedIdentifier = resourceIdentifier ?? url.standardizedFileURL.path
        self.id = resolvedIdentifier
        self.url = url
        self.resourceIdentifier = resolvedIdentifier
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.finderLabel = finderLabel
        self.finderOrder = finderOrder
    }
}

public enum MediaTypeRegistry {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp",
        "heic", "heif", "pdf", "eps", "ico", "icns", "psd",
        "webp", "avif", "dng", "raw",
    ]

    public static func isSupported(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
