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

@Test
func decoderRasterizesEveryPDFPage() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Imageview-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    var mediaBox = CGRect(x: 0, y: 0, width: 120, height: 80)
    let context = try #require(
        CGContext(url as CFURL, mediaBox: &mediaBox, nil)
    )
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(mediaBox)
    context.endPDFPage()
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(mediaBox)
    context.endPDFPage()
    context.closePDF()

    let first = try ImageDecoder().decode(url: url, page: 0)
    let second = try ImageDecoder().decode(url: url, page: 1)

    #expect(first.frameCount == 2)
    #expect(first.pixelSize == CGSize(width: 240, height: 160))
    #expect(second.frameCount == 2)
    #expect(second.pixelSize == CGSize(width: 240, height: 160))
}
