import CoreGraphics
import ImageIO

public enum ExportMetadata {
    public static func adjustedProperties(
        _ source: [CFString: Any],
        renderedImage: CGImage
    ) -> [CFString: Any] {
        var properties = source
        properties[kCGImagePropertyOrientation] = 1
        properties[kCGImagePropertyPixelWidth] = renderedImage.width
        properties[kCGImagePropertyPixelHeight] = renderedImage.height
        return properties
    }
}
