import Foundation

public struct MetadataRow: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public enum MetadataFormatter {
    public static func rows(from properties: [CFString: Any]) -> [MetadataRow] {
        flatten(dictionary: properties, prefix: nil)
    }

    private static func flatten(
        dictionary: [CFString: Any],
        prefix: String?
    ) -> [MetadataRow] {
        dictionary
            .map { (normalizedKey($0.key as String), $0.value) }
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            .flatMap { key, value -> [MetadataRow] in
                let path = prefix.map { "\($0).\(key)" } ?? key
                if let nested = value as? [CFString: Any] {
                    return flatten(dictionary: nested, prefix: path)
                }
                if let nested = value as? [String: Any] {
                    let bridged = Dictionary(uniqueKeysWithValues: nested.map {
                        ($0.key as CFString, $0.value)
                    })
                    return flatten(dictionary: bridged, prefix: path)
                }
                return [MetadataRow(key: path, value: string(from: value))]
            }
    }

    private static func normalizedKey(_ key: String) -> String {
        switch key {
        case "{Exif}":
            "EXIF"
        case "{TIFF}":
            "TIFF"
        case "{IPTC}":
            "IPTC"
        case "{GPS}":
            "GPS"
        case "{PNG}":
            "PNG"
        case "{GIF}":
            "GIF"
        default:
            key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        }
    }

    private static func string(from value: Any) -> String {
        if let array = value as? [Any] {
            return array.map(string(from:)).joined(separator: ", ")
        }
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        return String(describing: value)
    }
}
