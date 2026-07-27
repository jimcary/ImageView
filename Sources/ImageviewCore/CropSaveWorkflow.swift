import CoreGraphics
import Foundation
import ImageIO

public struct CropSaveWorkflow {
    private let decoder: ImageDecoder
    private let renderer: ImageRenderer
    private let exporter: ExportCoordinator

    public init(
        decoder: ImageDecoder = ImageDecoder(),
        renderer: ImageRenderer = ImageRenderer(),
        exporter: ExportCoordinator = ExportCoordinator()
    ) {
        self.decoder = decoder
        self.renderer = renderer
        self.exporter = exporter
    }

    public func save(
        sourceURL: URL,
        recipe: EditRecipe,
        destinationURL: URL,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        let decoded = try decoder.decode(url: sourceURL)
        let rendered = try renderer.render(decoded.image, recipe: recipe)
        try exporter.saveAs(
            image: rendered,
            sourceProperties: adjustedProperties(
                decoded.properties,
                renderedImage: rendered
            ),
            destinationURL: destinationURL,
            format: format,
            metadataPolicy: metadataPolicy
        )
    }

    public func overwrite(
        sourceURL: URL,
        recipe: EditRecipe,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        let decoded = try decoder.decode(url: sourceURL)
        let rendered = try renderer.render(decoded.image, recipe: recipe)
        try exporter.overwrite(
            image: rendered,
            sourceProperties: adjustedProperties(
                decoded.properties,
                renderedImage: rendered
            ),
            originalURL: sourceURL,
            format: format,
            metadataPolicy: metadataPolicy
        )
    }

    private func adjustedProperties(
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
