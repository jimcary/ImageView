import CoreGraphics
import Foundation
import Testing
@testable import ImageviewCore

@Test
func rendererCropsAndRotatesRealPixels() throws {
    let source = try TestImageFixtures.image(width: 60, height: 40)
    let recipe = EditRecipe(
        rotationQuarterTurns: 1,
        crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
    )

    let rendered = try ImageRenderer().render(source, recipe: recipe)

    #expect(rendered.width == 40)
    #expect(rendered.height == 30)
}

@Test
func decoderReadsPixelSizeAndPageCount() throws {
    let url = try TestImageFixtures.writePNG(width: 80, height: 50)
    defer { try? FileManager.default.removeItem(at: url) }

    let decoded = try ImageDecoder().decode(url: url)

    #expect(decoded.pixelSize == CGSize(width: 80, height: 50))
    #expect(decoded.frameCount == 1)
}
