import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public struct DecodedImage: @unchecked Sendable {
    public let image: CGImage
    public let properties: [CFString: Any]
    public let frameCount: Int
    public let duration: TimeInterval?
    public let typeIdentifier: String?

    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

public enum ImageDecodeError: Error, Equatable {
    case cannotOpen
    case pageOutOfRange
    case cannotDecode
    case orientationTransformFailed
}

public struct ImageDecoder {
    public init() {}

    public func decode(url: URL, page: Int = 0) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageDecodeError.cannotOpen
        }

        let frameCount = CGImageSourceGetCount(source)
        guard page >= 0, page < frameCount else {
            throw ImageDecodeError.pageOutOfRange
        }
        guard let sourceImage = CGImageSourceCreateImageAtIndex(
            source,
            page,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        ) else {
            throw ImageDecodeError.cannotDecode
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, page, nil)
            as? [CFString: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        let image = try orientedImage(sourceImage, exifOrientation: orientation)

        return DecodedImage(
            image: image,
            properties: properties,
            frameCount: frameCount,
            duration: frameDuration(from: properties),
            typeIdentifier: CGImageSourceGetType(source) as String?
        )
    }

    private func orientedImage(
        _ image: CGImage,
        exifOrientation: Int32
    ) throws -> CGImage {
        guard exifOrientation != 1 else {
            return image
        }

        let oriented = CIImage(cgImage: image)
            .oriented(forExifOrientation: exifOrientation)
        let extent = oriented.extent.integral
        let normalized = oriented.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        guard let output = CIContext(options: [.cacheIntermediates: false])
            .createCGImage(normalized, from: normalized.extent.integral) else {
            throw ImageDecodeError.orientationTransformFailed
        }
        return output
    }

    private func frameDuration(from properties: [CFString: Any]) -> TimeInterval? {
        guard let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return nil
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
            return unclamped.doubleValue
        }
        return (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
    }
}
