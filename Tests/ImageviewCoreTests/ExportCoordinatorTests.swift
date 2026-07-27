import Foundation
import ImageIO
import Testing
@testable import ImageviewCore

@Test
func exportMetadataMatchesRenderedPixelGeometry() throws {
    let rendered = try TestImageFixtures.image(width: 20, height: 10)
    let source: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyPixelWidth: 4_000,
        kCGImagePropertyPixelHeight: 3_000
    ]

    let adjusted = ExportMetadata.adjustedProperties(
        source,
        renderedImage: rendered
    )

    #expect(adjusted[kCGImagePropertyOrientation] as? Int == 1)
    #expect(adjusted[kCGImagePropertyPixelWidth] as? Int == 20)
    #expect(adjusted[kCGImagePropertyPixelHeight] as? Int == 10)
}

@Test
func failedOverwriteLeavesOriginalBytesUntouched() throws {
    let original = try TestImageFixtures.writePNG(width: 30, height: 20)
    defer { try? FileManager.default.removeItem(at: original) }
    let originalBytes = try Data(contentsOf: original)
    let image = try TestImageFixtures.image(width: 10, height: 10)
    let coordinator = ExportCoordinator(validator: { _, _ in false })

    #expect(throws: ExportError.validationFailed) {
        try coordinator.overwrite(
            image: image,
            sourceProperties: nil,
            originalURL: original,
            format: .png,
            metadataPolicy: .remove
        )
    }
    #expect(try Data(contentsOf: original) == originalBytes)
}

@Test
func failedReplacementAfterOriginalDisappearsRestoresOriginalBytes() throws {
    let original = try TestImageFixtures.writePNG(width: 30, height: 20)
    defer { try? FileManager.default.removeItem(at: original) }
    let originalBytes = try Data(contentsOf: original)
    let image = try TestImageFixtures.image(width: 10, height: 10)
    let coordinator = ExportCoordinator(
        replacement: { fileManager, originalURL, _ in
            try fileManager.removeItem(at: originalURL)
            throw CocoaError(.fileWriteUnknown)
        }
    )

    #expect(throws: CocoaError.self) {
        try coordinator.overwrite(
            image: image,
            sourceProperties: nil,
            originalURL: original,
            format: .png,
            metadataPolicy: .remove
        )
    }
    #expect(try Data(contentsOf: original) == originalBytes)
}

@Test
func saveAsProducesAReopenableImage() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewExport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let output = folder.appendingPathComponent("saved.jpg")
    let image = try TestImageFixtures.image(width: 45, height: 25)

    try ExportCoordinator().saveAs(
        image: image,
        sourceProperties: nil,
        destinationURL: output,
        format: .jpeg(quality: 0.75),
        metadataPolicy: .remove
    )

    let decoded = try ImageDecoder().decode(url: output)
    #expect(decoded.pixelSize == CGSize(width: 45, height: 25))
}

@Test
func defaultValidatorDecodesPixelsAndChecksExpectedDimensions() throws {
    let imageURL = try TestImageFixtures.writePNG(width: 45, height: 25)
    let corruptURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewCorrupt-\(UUID().uuidString).png")
    defer {
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: corruptURL)
    }
    try Data("not pixels".utf8).write(to: corruptURL)

    #expect(
        ExportCoordinator.defaultValidator(
            url: imageURL,
            expectedPixelSize: CGSize(width: 45, height: 25)
        )
    )
    #expect(
        !ExportCoordinator.defaultValidator(
            url: imageURL,
            expectedPixelSize: CGSize(width: 44, height: 25)
        )
    )
    #expect(
        !ExportCoordinator.defaultValidator(
            url: corruptURL,
            expectedPixelSize: CGSize(width: 45, height: 25)
        )
    )
}

@Test
func heifExportUsesTheHEIFTypeIdentifier() {
    #expect(ExportFormat.heif(quality: 0.9).fileExtension == "heif")
    #expect(ExportFormat.heif(quality: 0.9).typeIdentifier as String == "public.heif")
    #expect(ExportFormat.heic(quality: 0.9).typeIdentifier as String == "public.heic")
}
