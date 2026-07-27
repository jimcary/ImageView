import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ImageviewCore

@Test
func cropSaveCanBeDecodedAndHasRequestedDimensions() throws {
    let sourceURL = try TestImageFixtures.writePNG(width: 120, height: 80)
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageviewCrop-\(UUID().uuidString).png")
    defer {
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: outputURL)
    }
    let recipe = EditRecipe(
        crop: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    )

    try CropSaveWorkflow().save(
        sourceURL: sourceURL,
        recipe: recipe,
        destinationURL: outputURL,
        format: .png,
        metadataPolicy: .remove
    )

    let decoded = try ImageDecoder().decode(url: outputURL)
    #expect(decoded.pixelSize == CGSize(width: 60, height: 40))
}

@Test
func cropOverwriteAtomicallyReplacesOriginalWithDecodablePixels() throws {
    let original = try TestImageFixtures.writePNG(width: 100, height: 60)
    defer { try? FileManager.default.removeItem(at: original) }
    let recipe = EditRecipe(
        rotationQuarterTurns: 1,
        crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
    )

    try CropSaveWorkflow().overwrite(
        sourceURL: original,
        recipe: recipe,
        format: .png,
        metadataPolicy: .preserve
    )

    let decoded = try ImageDecoder().decode(url: original)
    #expect(decoded.pixelSize == CGSize(width: 30, height: 100))
}

@Test
func cropOverwriteRejectsMultiPageSourcesWithoutChangingThem() throws {
    let original = try TestImageFixtures.writeMultiPageTIFF(width: 40, height: 30)
    defer { try? FileManager.default.removeItem(at: original) }
    let originalBytes = try Data(contentsOf: original)

    #expect(throws: ExportError.multiImageSourceUnsupported) {
        try CropSaveWorkflow().overwrite(
            sourceURL: original,
            recipe: EditRecipe(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)),
            format: .tiff,
            metadataPolicy: .preserve
        )
    }

    let source = try #require(CGImageSourceCreateWithURL(original as CFURL, nil))
    #expect(CGImageSourceGetCount(source) == 2)
    #expect(try Data(contentsOf: original) == originalBytes)
}
