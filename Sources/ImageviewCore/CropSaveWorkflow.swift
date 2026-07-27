import CoreGraphics
import Foundation

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
            sourceProperties: ExportMetadata.adjustedProperties(
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
        guard decoded.frameCount == 1 else {
            throw ExportError.multiImageSourceUnsupported
        }
        let rendered = try renderer.render(decoded.image, recipe: recipe)
        try exporter.overwrite(
            image: rendered,
            sourceProperties: ExportMetadata.adjustedProperties(
                decoded.properties,
                renderedImage: rendered
            ),
            originalURL: sourceURL,
            format: format,
            metadataPolicy: metadataPolicy
        )
    }
}
