import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public struct DecodedImage: @unchecked Sendable {
    public let image: CGImage
    public let properties: [CFString: Any]
    public let index: Int
    public let frameCount: Int
    public let duration: TimeInterval?
    public let typeIdentifier: String?
    public let playbackKind: MediaPlaybackKind

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
        if url.pathExtension.lowercased() == "pdf" {
            return try decodePDF(url: url, page: page)
        }
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
        let typeIdentifier = CGImageSourceGetType(source) as String?

        return DecodedImage(
            image: image,
            properties: properties,
            index: page,
            frameCount: frameCount,
            duration: ImageFrameTiming.duration(from: properties),
            typeIdentifier: typeIdentifier,
            playbackKind: MediaPlaybackKind.classify(
                url: url,
                typeIdentifier: typeIdentifier,
                frameCount: frameCount
            )
        )
    }

    private func decodePDF(url: URL, page: Int) throws -> DecodedImage {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw ImageDecodeError.cannotOpen
        }
        let pageCount = document.numberOfPages
        guard page >= 0, page < pageCount,
              let pdfPage = document.page(at: page + 1) else {
            throw ImageDecodeError.pageOutOfRange
        }

        let box = pdfPage.getBoxRect(.mediaBox)
        guard box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else {
            throw ImageDecodeError.cannotDecode
        }
        let rotation = abs(pdfPage.rotationAngle) % 180
        let pointWidth = rotation == 90 ? box.height : box.width
        let pointHeight = rotation == 90 ? box.width : box.height
        let maximumDimension: CGFloat = 8_192
        let maximumPixels: CGFloat = 64_000_000
        let dimensionScale = maximumDimension / max(pointWidth, pointHeight)
        let pixelScale = sqrt(maximumPixels / max(pointWidth * pointHeight, 1))
        let scale = min(2, dimensionScale, pixelScale)
        let width = max(Int((pointWidth * scale).rounded(.up)), 1)
        let height = max(Int((pointHeight * scale).rounded(.up)), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageDecodeError.cannotDecode
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.concatenate(
            pdfPage.getDrawingTransform(
                .mediaBox,
                rect: target,
                rotate: 0,
                preserveAspectRatio: true
            )
        )
        context.drawPDFPage(pdfPage)
        guard let image = context.makeImage() else {
            throw ImageDecodeError.cannotDecode
        }

        return DecodedImage(
            image: image,
            properties: [
                kCGImagePropertyPixelWidth: width,
                kCGImagePropertyPixelHeight: height,
            ],
            index: page,
            frameCount: pageCount,
            duration: nil,
            typeIdentifier: "com.adobe.pdf",
            playbackKind: .document
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

}

enum ImageFrameTiming {
    static func duration(from properties: [CFString: Any]) -> TimeInterval? {
        let candidates: [(CFString, CFString, CFString)] = [
            (
                kCGImagePropertyGIFDictionary,
                kCGImagePropertyGIFUnclampedDelayTime,
                kCGImagePropertyGIFDelayTime
            ),
            (
                kCGImagePropertyPNGDictionary,
                kCGImagePropertyAPNGUnclampedDelayTime,
                kCGImagePropertyAPNGDelayTime
            ),
            (
                kCGImagePropertyWebPDictionary,
                kCGImagePropertyWebPUnclampedDelayTime,
                kCGImagePropertyWebPDelayTime
            ),
            (
                kCGImagePropertyHEICSDictionary,
                kCGImagePropertyHEICSUnclampedDelayTime,
                kCGImagePropertyHEICSDelayTime
            ),
        ]

        for (dictionaryKey, unclampedKey, delayKey) in candidates {
            guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else {
                continue
            }
            if let value = dictionary[unclampedKey] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[delayKey] as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }
}
