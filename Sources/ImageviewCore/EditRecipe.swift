import CoreGraphics

public struct NormalizedRect: Equatable, Hashable, Sendable {
    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        self.x = clampedX
        self.y = clampedY
        self.width = min(max(width, 0), 1 - clampedX)
        self.height = min(max(height, 0), 1 - clampedY)
    }
}

public struct EditRecipe: Equatable, Hashable, Sendable {
    public let rotationQuarterTurns: Int
    public let flipHorizontal: Bool
    public let flipVertical: Bool
    public let crop: NormalizedRect

    public init(
        rotationQuarterTurns: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        crop: NormalizedRect = .full
    ) {
        self.rotationQuarterTurns = ((rotationQuarterTurns % 4) + 4) % 4
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.crop = crop
    }
}
