import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImageFixtures {
    static func image(width: Int = 60, height: Int = 40) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError.contextCreationFailed
        }

        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))

        guard let image = context.makeImage() else {
            throw FixtureError.imageCreationFailed
        }
        return image
    }

    static func quadrantImage(width: Int = 80, height: Int = 60) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError.contextCreationFailed
        }

        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2
        for (color, rect) in [
            (CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)),
            (CGColor(red: 0, green: 1, blue: 0, alpha: 1), CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight)),
            (CGColor(red: 0, green: 0, blue: 1, alpha: 1), CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)),
            (CGColor(red: 1, green: 1, blue: 0, alpha: 1), CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)),
        ] {
            context.setFillColor(color)
            context.fill(rect)
        }
        guard let image = context.makeImage() else {
            throw FixtureError.imageCreationFailed
        }
        return image
    }

    static func pixelRGBA(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        context.draw(
            image,
            in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height)
        )
        return bytes
    }

    static func writePNG(width: Int = 60, height: Int = 40) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageviewFixture-\(UUID().uuidString).png")
        let image = try image(width: width, height: height)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.finalizeFailed
        }
        return url
    }

    static func writeMultiPageTIFF(width: Int = 60, height: Int = 40) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageviewFixture-\(UUID().uuidString).tiff")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.tiff.identifier as CFString,
            2,
            nil
        ) else {
            throw FixtureError.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, try image(width: width, height: height), nil)
        CGImageDestinationAddImage(destination, try quadrantImage(width: width, height: height), nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.finalizeFailed
        }
        return url
    }

    enum FixtureError: Error {
        case contextCreationFailed
        case imageCreationFailed
        case destinationCreationFailed
        case finalizeFailed
    }
}
