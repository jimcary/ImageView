import CoreGraphics
import Foundation
import ImageIO

public enum ThumbnailDecodeError: Error, Equatable {
    case cannotOpen
    case cannotDecode
}

public struct ThumbnailDecoder: Sendable {
    public init() {}

    public func decode(url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ThumbnailDecodeError.cannotOpen
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw ThumbnailDecodeError.cannotDecode
        }
        return thumbnail
    }
}
