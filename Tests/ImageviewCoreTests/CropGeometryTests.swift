import CoreGraphics
import Testing
@testable import ImageviewCore

@Test
func dragPointsProduceAClampedNormalizedSelection() throws {
    let selection = try #require(
        CropGeometry.normalizedSelection(
            from: CGPoint(x: 30, y: 10),
            to: CGPoint(x: 130, y: 90),
            inside: CGRect(x: 10, y: 10, width: 100, height: 50)
        )
    )

    #expect(selection == NormalizedRect(x: 0.2, y: 0, width: 0.8, height: 1))
}

@Test
func reverseDragOutsideBoundsKeepsTheIntersectingSelection() throws {
    let selection = try #require(
        CropGeometry.normalizedSelection(
            from: CGPoint(x: 120, y: 80),
            to: CGPoint(x: -20, y: -30),
            inside: CGRect(x: 10, y: 10, width: 100, height: 50)
        )
    )

    #expect(selection == .full)
}

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

@Test
func tinyCropHitTestingChoosesTheNearestEdgeOnEachAxis() {
    let crop = CGRect(x: 40, y: 40, width: 8, height: 8)

    #expect(
        CropGeometry.resizeEdges(
            at: CGPoint(x: 47, y: 41),
            cropRect: crop,
            hitDistance: 12
        ) == [.right, .top]
    )
    #expect(
        CropGeometry.resizeEdges(
            at: CGPoint(x: 41, y: 47),
            cropRect: crop,
            hitDistance: 12
        ) == [.left, .bottom]
    )
}

@Test
func resizingPastBoundsKeepsTheOppositeEdgesStationary() {
    let original = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    let imageRect = CGRect(x: 0, y: 0, width: 100, height: 100)

    let leftPastRight = CropGeometry.resizedSelection(
        original,
        from: CGPoint(x: 25, y: 50),
        to: CGPoint(x: 120, y: 50),
        imageRect: imageRect,
        edges: [.left],
        minimumSize: 0.01
    )
    let topOutside = CropGeometry.resizedSelection(
        original,
        from: CGPoint(x: 50, y: 25),
        to: CGPoint(x: 50, y: -50),
        imageRect: imageRect,
        edges: [.top],
        minimumSize: 0.01
    )

    #expect(abs(leftPastRight.x - 0.74) < 0.0001)
    #expect(abs(leftPastRight.width - 0.01) < 0.0001)
    #expect(leftPastRight.y == 0.25)
    #expect(leftPastRight.height == 0.5)
    #expect(topOutside == NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 0.75))
}

@Test
func movingCropOutsideBoundsPreservesItsSize() {
    let original = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    let moved = CropGeometry.resizedSelection(
        original,
        from: CGPoint(x: 50, y: 50),
        to: CGPoint(x: -100, y: 200),
        imageRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        edges: [.move],
        minimumSize: 0.01
    )

    #expect(moved == NormalizedRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
}
