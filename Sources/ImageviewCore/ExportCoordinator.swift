import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: Equatable, Sendable {
    case jpeg(quality: Double)
    case png
    case tiff
    case heic(quality: Double)

    public var fileExtension: String {
        switch self {
        case .jpeg:
            "jpg"
        case .png:
            "png"
        case .tiff:
            "tiff"
        case .heic:
            "heic"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .jpeg:
            UTType.jpeg.identifier as CFString
        case .png:
            UTType.png.identifier as CFString
        case .tiff:
            UTType.tiff.identifier as CFString
        case .heic:
            UTType.heic.identifier as CFString
        }
    }

    var quality: Double? {
        switch self {
        case let .jpeg(quality), let .heic(quality):
            min(max(quality, 0), 1)
        case .png, .tiff:
            nil
        }
    }
}

public enum MetadataPolicy: Sendable {
    case preserve
    case remove
}

public enum ExportError: Error, Equatable {
    case targetExists
    case cannotCreateDestination
    case finalizeFailed
    case validationFailed
}

public struct ExportCoordinator {
    private let fileManager: FileManager
    private let validator: (URL) -> Bool

    public init(
        fileManager: FileManager = .default,
        validator: @escaping (URL) -> Bool = ExportCoordinator.defaultValidator
    ) {
        self.fileManager = fileManager
        self.validator = validator
    }

    public func saveAs(
        image: CGImage,
        sourceProperties: [CFString: Any]?,
        destinationURL: URL,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw ExportError.targetExists
        }
        let temporaryURL = siblingTemporaryURL(for: destinationURL, format: format)
        try writeAndValidate(
            image: image,
            sourceProperties: sourceProperties,
            temporaryURL: temporaryURL,
            format: format,
            metadataPolicy: metadataPolicy
        )

        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    public func overwrite(
        image: CGImage,
        sourceProperties: [CFString: Any]?,
        originalURL: URL,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        let temporaryURL = siblingTemporaryURL(for: originalURL, format: format)
        try writeAndValidate(
            image: image,
            sourceProperties: sourceProperties,
            temporaryURL: temporaryURL,
            format: format,
            metadataPolicy: metadataPolicy
        )

        do {
            _ = try fileManager.replaceItemAt(
                originalURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func writeAndValidate(
        image: CGImage,
        sourceProperties: [CFString: Any]?,
        temporaryURL: URL,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws {
        var shouldRemoveTemporaryFile = true
        defer {
            if shouldRemoveTemporaryFile,
               fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            format.typeIdentifier,
            1,
            nil
        ) else {
            throw ExportError.cannotCreateDestination
        }

        var properties: [CFString: Any]
        switch metadataPolicy {
        case .preserve:
            properties = sourceProperties ?? [:]
        case .remove:
            properties = [:]
        }
        if let quality = format.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.finalizeFailed
        }
        guard validator(temporaryURL) else {
            throw ExportError.validationFailed
        }
        shouldRemoveTemporaryFile = false
    }

    private func siblingTemporaryURL(for destination: URL, format: ExportFormat) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).imageview-\(UUID().uuidString).\(format.fileExtension)"
        )
    }

    public static func defaultValidator(url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return false
        }
        return width.intValue > 0 && height.intValue > 0
    }
}
