import Testing
@testable import ImageviewCore

@Test
func cropTransactionRequiresTheSameCurrentAndDecodedSource() {
    let transaction = CropTransaction(
        mediaID: "first",
        decodeGeneration: 8,
        subimageIndex: 0,
        originalRecipe: EditRecipe(rotationQuarterTurns: 1, flipHorizontal: true)
    )

    #expect(
        transaction.matches(
            currentMediaID: "first",
            decodedMediaID: "first",
            decodeGeneration: 8,
            subimageIndex: 0
        )
    )
    #expect(
        !transaction.matches(
            currentMediaID: "second",
            decodedMediaID: "first",
            decodeGeneration: 8,
            subimageIndex: 0
        )
    )
    #expect(
        !transaction.matches(
            currentMediaID: "first",
            decodedMediaID: "second",
            decodeGeneration: 8,
            subimageIndex: 0
        )
    )
    #expect(
        !transaction.matches(
            currentMediaID: "first",
            decodedMediaID: "first",
            decodeGeneration: 9,
            subimageIndex: 0
        )
    )
}

@Test
func cropTransactionRetainsTheCompleteRollbackRecipe() {
    let recipe = EditRecipe(
        rotationQuarterTurns: 3,
        flipHorizontal: true,
        flipVertical: true,
        crop: NormalizedRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6)
    )

    let transaction = CropTransaction(
        mediaID: "fixture",
        decodeGeneration: 3,
        subimageIndex: 0,
        originalRecipe: recipe
    )

    #expect(transaction.originalRecipe == recipe)
}
