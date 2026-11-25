import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import libwebp

public enum ExportFormat: Equatable, Sendable {
    case jpeg(quality: Double)
    case png
    case gif
    case webp(quality: Double)
    case tiff
    case heic(quality: Double)
    case heif(quality: Double)

    public var fileExtension: String {
        switch self {
        case .jpeg:
            "jpg"
        case .png:
            "png"
        case .gif:
            "gif"
        case .webp:
            "webp"
        case .tiff:
            "tiff"
        case .heic:
            "heic"
        case .heif:
            "heif"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .jpeg:
            UTType.jpeg.identifier as CFString
        case .png:
            UTType.png.identifier as CFString
        case .gif:
            UTType.gif.identifier as CFString
        case .webp:
            "org.webmproject.webp" as CFString
        case .tiff:
            UTType.tiff.identifier as CFString
        case .heic:
            UTType.heic.identifier as CFString
        case .heif:
            UTType.heif.identifier as CFString
        }
    }

    var quality: Double? {
        switch self {
        case let .jpeg(quality), let .heic(quality), let .heif(quality), let .webp(quality):
            min(max(quality, 0), 1)
        case .png, .gif, .tiff:
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
    case multiImageSourceUnsupported
}

public struct ExportCoordinator {
    private let fileManager: FileManager
    private let validator: (URL, CGSize) -> Bool
    private let replacement: (FileManager, URL, URL) throws -> Void

    public init(
        fileManager: FileManager = .default,
        validator: @escaping (URL, CGSize) -> Bool = ExportCoordinator.defaultValidator,
        replacement: @escaping (FileManager, URL, URL) throws -> Void = {
            fileManager, originalURL, temporaryURL in
            _ = try fileManager.replaceItemAt(
                originalURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        }
    ) {
        self.fileManager = fileManager
        self.validator = validator
        self.replacement = replacement
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
            if (error as? CocoaError)?.code == .fileWriteFileExists {
                throw ExportError.targetExists
            }
            throw error
        }
    }

    @discardableResult
    public func saveBesideSource(
        image: CGImage,
        sourceProperties: [CFString: Any]?,
        sourceURL: URL,
        format: ExportFormat,
        metadataPolicy: MetadataPolicy
    ) throws -> URL {
        let folder = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let name = number == 1 ? baseName : "\(baseName)\(number)"
            let destination = folder.appendingPathComponent("\(name).\(format.fileExtension)")
            do {
                try saveAs(
                    image: image,
                    sourceProperties: sourceProperties,
                    destinationURL: destination,
                    format: format,
                    metadataPolicy: metadataPolicy
                )
                return destination
            } catch ExportError.targetExists {
                number += 1
            }
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
        let backupURL = siblingBackupURL(for: originalURL)

        do {
            try fileManager.copyItem(at: originalURL, to: backupURL)
            try replacement(fileManager, originalURL, temporaryURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path) {
                if fileManager.fileExists(atPath: originalURL.path) {
                    try? fileManager.removeItem(at: originalURL)
                }
                do {
                    try fileManager.copyItem(at: backupURL, to: originalURL)
                    try? fileManager.removeItem(at: backupURL)
                } catch {
                    try? fileManager.removeItem(at: temporaryURL)
                    throw error
                }
            }
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

        if case .webp = format {
            try writeWebP(image, to: temporaryURL, quality: format.quality ?? 0.9)
        } else {
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
        }
        guard validator(
            temporaryURL,
            CGSize(width: image.width, height: image.height)
        ) else {
            throw ExportError.validationFailed
        }
        shouldRemoveTemporaryFile = false
    }

    private func writeWebP(_ image: CGImage, to url: URL, quality: Double) throws {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= 16_383, height <= 16_383,
              width * height <= 100_000_000 else {
            throw ExportError.cannotCreateDestination
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw ExportError.cannotCreateDestination }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha > 0 && alpha < 255 {
                for channel in 0..<3 {
                    pixels[index + channel] = UInt8(min(255, (Int(pixels[index + channel]) * 255 + alpha / 2) / alpha))
                }
            }
        }
        var output: UnsafeMutablePointer<UInt8>?
        let size = pixels.withUnsafeBufferPointer {
            WebPEncodeRGBA($0.baseAddress, Int32(width), Int32(height), Int32(width * 4), Float(quality * 100), &output)
        }
        guard size > 0, let output else { throw ExportError.finalizeFailed }
        defer { WebPFree(output) }
        try Data(bytes: output, count: size).write(to: url)
    }

    private func siblingTemporaryURL(for destination: URL, format: ExportFormat) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".imageview-\(UUID().uuidString).\(format.fileExtension)"
        )
    }

    private func siblingBackupURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).imageview-backup-\(UUID().uuidString)"
        )
    }

    public static func defaultValidator(
        url: URL,
        expectedPixelSize: CGSize
    ) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            return false
        }
        return image.width == Int(expectedPixelSize.width)
            && image.height == Int(expectedPixelSize.height)
    }
}
