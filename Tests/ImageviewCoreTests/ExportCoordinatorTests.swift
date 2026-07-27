import Foundation
import Testing
@testable import ImageviewCore

@Test
func failedOverwriteLeavesOriginalBytesUntouched() throws {
    let original = try TestImageFixtures.writePNG(width: 30, height: 20)
    defer { try? FileManager.default.removeItem(at: original) }
    let originalBytes = try Data(contentsOf: original)
    let image = try TestImageFixtures.image(width: 10, height: 10)
    let coordinator = ExportCoordinator(validator: { _ in false })

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
