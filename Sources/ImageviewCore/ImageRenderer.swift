import CoreGraphics
import CoreImage
import ImageIO

public enum ImageRenderError: Error, Equatable {
    case emptyCrop
    case cropFailed
    case renderFailed
    case invalidSize
}

public struct ImageRenderer {
    public init() {}

    public func render(_ source: CGImage, recipe: EditRecipe) throws -> CGImage {
        if let size = recipe.resize, !size.isValid {
            throw ImageRenderError.invalidSize
        }
        var output = CIImage(cgImage: source)
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

        let transformedExtent = output.extent.integral
        let normalized = output.transformed(
            by: CGAffineTransform(
                translationX: -transformedExtent.minX,
                y: -transformedExtent.minY
            )
        )
        guard let transformed = CIContext(options: [.cacheIntermediates: false])
            .createCGImage(normalized, from: normalized.extent.integral) else {
            throw ImageRenderError.renderFailed
        }

        let cropRect = CropGeometry(crop: recipe.crop)
            .pixelRect(imageSize: CGSize(width: transformed.width, height: transformed.height))
        guard cropRect.width >= 1, cropRect.height >= 1 else {
            throw ImageRenderError.emptyCrop
        }
        guard let cropped = transformed.cropping(to: cropRect) else {
            throw ImageRenderError.cropFailed
        }
        guard let size = recipe.resize else {
            return cropped
        }
        let resized = CIImage(cgImage: cropped).transformed(by: CGAffineTransform(
            scaleX: CGFloat(size.width) / CGFloat(cropped.width),
            y: CGFloat(size.height) / CGFloat(cropped.height)
        ))
        guard let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(
            resized,
            from: CGRect(x: 0, y: 0, width: size.width, height: size.height)
        ) else {
            throw ImageRenderError.renderFailed
        }
        return result
    }
}
