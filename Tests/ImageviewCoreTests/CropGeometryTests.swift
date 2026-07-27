import CoreGraphics
import Testing
@testable import ImageviewCore

@Test
func normalizedCropConvertsToIntegralSourcePixels() {
    let crop = NormalizedRect(x: 0.25, y: 0.10, width: 0.50, height: 0.40)

    let pixels = CropGeometry(crop: crop)
        .pixelRect(imageSize: CGSize(width: 4000, height: 3000))

    #expect(pixels == CGRect(x: 1000, y: 300, width: 2000, height: 1200))
}

@Test
func normalizedCropClampsToImageBounds() {
    let crop = NormalizedRect(x: -0.2, y: 0.8, width: 1.4, height: 0.5)

    #expect(crop == NormalizedRect(x: 0, y: 0.8, width: 1, height: 0.2))
}

@Test
func squareConstraintKeepsCenterAndFitsInsideBounds() {
    let proposed = CGRect(x: 10, y: 10, width: 160, height: 100)
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 120)

    let result = CropGeometry.constrain(proposed, to: .square, inside: bounds)

    #expect(result == CGRect(x: 40, y: 10, width: 100, height: 100))
}

@Test
func allDocumentedCropRatiosExposeExpectedValues() {
    #expect(CropAspect.oneByTwo.ratio == 0.5)
    #expect(CropAspect.twoByOne.ratio == 2)
    #expect(CropAspect.twoByThree.ratio == 2.0 / 3.0)
    #expect(CropAspect.threeByTwo.ratio == 1.5)
    #expect(CropAspect.threeByFour.ratio == 0.75)
    #expect(CropAspect.fourByThree.ratio == 4.0 / 3.0)
    #expect(CropAspect.nineBySixteen.ratio == 9.0 / 16.0)
    #expect(CropAspect.sixteenByNine.ratio == 16.0 / 9.0)
}
