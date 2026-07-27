import Foundation

public enum MediaKind: String, Sendable {
    case image
    case animation
    case document
    case raw
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
