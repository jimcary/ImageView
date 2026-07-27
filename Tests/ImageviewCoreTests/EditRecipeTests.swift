import Testing
@testable import ImageviewCore

@Test
func quarterTurnsNormalizeAndFlipsRemainIndependent() {
    let recipe = EditRecipe(
        rotationQuarterTurns: 5,
        flipHorizontal: true,
        flipVertical: false,
        crop: .full
    )

    #expect(recipe.rotationQuarterTurns == 1)
    #expect(recipe.flipHorizontal)
    #expect(!recipe.flipVertical)
}

@Test
func negativeQuarterTurnsNormalizeClockwise() {
    let recipe = EditRecipe(rotationQuarterTurns: -1)

    #expect(recipe.rotationQuarterTurns == 3)
}
