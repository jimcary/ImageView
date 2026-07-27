import Testing
@testable import ImageviewCore

@Test
func onlyNewestDecodeGenerationCanPublish() {
    var generations = DecodeGeneration()
    let first = generations.begin()
    let second = generations.begin()

    #expect(!generations.isCurrent(first))
    #expect(generations.isCurrent(second))
}

@Test
func invalidatingGenerationRejectsOutstandingResult() {
    var generations = DecodeGeneration()
    let outstanding = generations.begin()

    generations.invalidate()

    #expect(!generations.isCurrent(outstanding))
}
