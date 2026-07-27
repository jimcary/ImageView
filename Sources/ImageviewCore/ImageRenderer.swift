import CoreGraphics
import CoreImage
import ImageIO

public enum ImageRenderError: Error, Equatable {
    case emptyCrop
    case cropFailed
    case renderFailed
}

public struct ImageRenderer {
    public init() {}

    public func render(_ source: CGImage, recipe: EditRecipe) throws -> CGImage {
        let cropRect = CropGeometry(crop: recipe.crop)
            .pixelRect(imageSize: CGSize(width: source.width, height: source.height))
        guard cropRect.width >= 1, cropRect.height >= 1 else {
            throw ImageRenderError.emptyCrop
        }
        guard let cropped = source.cropping(to: cropRect) else {
            throw ImageRenderError.cropFailed
        }

        var output = CIImage(cgImage: cropped)
        if recipe.flipHorizontal {
            output = output.oriented(.upMirrored)
        }
        if recipe.flipVertical {
            output = output.oriented(.downMirrored)
        }

        let orientation: CGImagePropertyOrientation
        switch recipe.rotationQuarterTurns {
        case 1:
            orientation = .right
        case 2:
            orientation = .down
        case 3:
            orientation = .left
        default:
            orientation = .up
        }
        output = output.oriented(orientation)

        let extent = output.extent.integral
        let normalized = output.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        guard let rendered = CIContext(options: [.cacheIntermediates: false])
            .createCGImage(normalized, from: normalized.extent.integral) else {
            throw ImageRenderError.renderFailed
        }
        return rendered
    }
}
