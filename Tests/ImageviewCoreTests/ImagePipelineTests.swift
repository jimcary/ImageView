import CoreGraphics
import Foundation
import Testing
@testable import ImageviewCore

@Test
func rendererResizesAfterRotatingAndCropping() throws {
    let source = try TestImageFixtures.quadrantImage(width: 80, height: 60)
    let cropped = try ImageRenderer().render(
        source,
        recipe: EditRecipe(rotationQuarterTurns: 1, crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
    )
    let resized = try ImageRenderer().render(
        source,
        recipe: EditRecipe(rotationQuarterTurns: 1, crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1), resize: PixelSize(width: 15, height: 40))
    )

    #expect(resized.width == 15)
    #expect(resized.height == 40)
    #expect(TestImageFixtures.pixelRGBA(resized, x: 3, y: 3) == TestImageFixtures.pixelRGBA(cropped, x: 6, y: 6))
}

@Test
func rendererRejectsInvalidOrExcessiveResize() throws {
    let source = try TestImageFixtures.image()
    for size in [
        PixelSize(width: 0, height: 10),
        PixelSize(width: 16_385, height: 1),
        PixelSize(width: 10_001, height: 10_000),
    ] {
        #expect(throws: ImageRenderError.invalidSize) {
            try ImageRenderer().render(source, recipe: EditRecipe(resize: size))
        }
    }
}

@Test
func rendererCropsAndRotatesRealPixels() throws {
    let source = try TestImageFixtures.image(width: 60, height: 40)
    let recipe = EditRecipe(
        rotationQuarterTurns: 1,
        crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
    )

    let rendered = try ImageRenderer().render(source, recipe: recipe)

    #expect(rendered.width == 20)
    #expect(rendered.height == 60)
}

@Test
func rendererAppliesDisplaySpaceCropAfterRotationsAndFlips() throws {
    let source = try TestImageFixtures.quadrantImage(width: 80, height: 60)
    let crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
    let transforms = [
        EditRecipe(rotationQuarterTurns: 1),
        EditRecipe(flipHorizontal: true),
        EditRecipe(flipVertical: true),
    ]
    let renderer = ImageRenderer()

    for transform in transforms {
        let displayed = try renderer.render(source, recipe: transform)
        let cropRect = CropGeometry(crop: crop).pixelRect(
            imageSize: CGSize(width: displayed.width, height: displayed.height)
        )
        let expected = try #require(displayed.cropping(to: cropRect))
        let actual = try renderer.render(
            source,
            recipe: EditRecipe(
                rotationQuarterTurns: transform.rotationQuarterTurns,
                flipHorizontal: transform.flipHorizontal,
                flipVertical: transform.flipVertical,
                crop: crop
            )
        )

        #expect(actual.width == expected.width)
        #expect(actual.height == expected.height)
        #expect(TestImageFixtures.pixelRGBA(actual, x: 1, y: 1)
            == TestImageFixtures.pixelRGBA(expected, x: 1, y: 1))
        #expect(TestImageFixtures.pixelRGBA(
            actual,
            x: max(actual.width - 2, 0),
            y: max(actual.height - 2, 0)
        ) == TestImageFixtures.pixelRGBA(
            expected,
            x: max(expected.width - 2, 0),
            y: max(expected.height - 2, 0)
        ))
    }
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
