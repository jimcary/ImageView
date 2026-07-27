import Foundation

public struct OpenWithApplication: Equatable, Sendable {
    public let url: URL
    public let displayName: String

    public init(url: URL, displayName: String) {
        self.url = url
        self.displayName = displayName
    }
}

public enum OpenWithApplications {
    public static func rows(
        from urls: [URL],
        excluding excludedURL: URL?,
        displayName: (URL) -> String
    ) -> [OpenWithApplication] {
        let excluded = excludedURL?.standardizedFileURL
        var seen = Set<URL>()

        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard standardizedURL != excluded,
                  seen.insert(standardizedURL).inserted else {
                return nil
            }
            return OpenWithApplication(
                url: standardizedURL,
                displayName: displayName(standardizedURL)
            )
        }
        .sorted {
            let comparison = $0.displayName.localizedStandardCompare($1.displayName)
            if comparison == .orderedSame {
                return $0.url.path < $1.url.path
            }
            return comparison == .orderedAscending
        }
    }
}
