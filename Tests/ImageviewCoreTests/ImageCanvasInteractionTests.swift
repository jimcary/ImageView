import Testing
@testable import ImageviewCore

@Test
func plainImageDragStartsCropAndOptionDragPans() {
    #expect(
        ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: true,
            optionPressed: false
        ) == .cropSelection
    )
    #expect(
        ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: true,
            optionPressed: true
        ) == .pan
    )
    #expect(
        ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: false,
            optionPressed: false
        ) == nil
    )
}
