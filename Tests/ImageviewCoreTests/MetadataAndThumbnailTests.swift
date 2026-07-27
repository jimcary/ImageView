import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ImageviewCore

@Test
func metadataFormatterFlattensExifWithoutLosingDisplayedKeys() {
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifFNumber: 2.8,
        ],
        kCGImagePropertyPixelWidth: 6_000,
    ]

    let rows = MetadataFormatter.rows(from: properties)

    #expect(rows.contains(MetadataRow(key: "EXIF.FNumber", value: "2.8")))
    #expect(rows.contains(MetadataRow(key: "PixelWidth", value: "6000")))
}

@Test
func thumbnailDecoderBoundsLongestPixelDimension() throws {
    let url = try TestImageFixtures.writePNG(width: 400, height: 200)
    defer { try? FileManager.default.removeItem(at: url) }

    let thumbnail = try ThumbnailDecoder().decode(url: url, maxPixelSize: 80)

    #expect(thumbnail.width == 80)
    #expect(thumbnail.height == 40)
}
