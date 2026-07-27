import Foundation

public struct FolderScanner: Sendable {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .fileResourceIdentifierKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .labelNumberKey,
    ]

    public init() {}

    public func scan(folder: URL, recursive: Bool) throws -> [MediaItem] {
        let urls: [URL]
        if recursive {
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw CocoaError(.fileReadUnknown)
            }
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: [.skipsHiddenFiles]
            )
        }

        return urls.enumerated().compactMap { finderOrder, url in
            guard MediaTypeRegistry.isSupported(url: url) else {
                return nil
            }
            guard let values = try? url.resourceValues(forKeys: Self.resourceKeys),
                  values.isRegularFile != false else {
                return nil
            }

            let identifier = values.fileResourceIdentifier
                .map(String.init(describing:))
                ?? url.standardizedFileURL.path
            return MediaItem(
                url: url,
                resourceIdentifier: identifier,
                fileSize: values.fileSize.map(Int64.init),
                createdAt: values.creationDate,
                modifiedAt: values.contentModificationDate,
                finderLabel: values.labelNumber,
                finderOrder: finderOrder
            )
        }
    }
}
