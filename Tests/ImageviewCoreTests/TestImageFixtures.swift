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

    enum FixtureError: Error {
        case contextCreationFailed
        case imageCreationFailed
        case destinationCreationFailed
        case finalizeFailed
    }
}
