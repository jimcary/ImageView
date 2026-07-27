import Foundation

public enum MediaPlaybackKind: Equatable, Sendable {
    case still
    case animation
    case document

    public static func classify(
        url: URL,
        typeIdentifier: String? = nil,
        frameCount: Int
    ) -> MediaPlaybackKind {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "pdf" || typeIdentifier == "com.adobe.pdf" {
            return .document
        }
        guard frameCount > 1 else {
            return .still
        }

        let animatedExtensions: Set<String> = ["gif", "png", "webp", "heics"]
        let animatedTypes: Set<String> = [
            "com.compuserve.gif",
            "public.png",
            "org.webmproject.webp",
            "public.heics",
        ]
        if animatedExtensions.contains(pathExtension)
            || typeIdentifier.map(animatedTypes.contains) == true {
            return .animation
        }
        return .document
    }
}

public enum FramePlaybackPolicy {
    public static func safeDelay(_ duration: TimeInterval?) -> TimeInterval {
        guard let duration, duration > 0 else {
            return 0.1
        }
        return min(max(duration, 0.02), 10)
    }

    public static func nextFrame(after current: Int, frameCount: Int) -> Int {
        guard frameCount > 1 else {
            return 0
        }
        return (max(current, 0) + 1) % frameCount
    }
}

public struct MediaSubimageKey: Hashable, Sendable {
    public let mediaID: MediaItem.ID
    public let index: Int

    public init(mediaID: MediaItem.ID, index: Int) {
        self.mediaID = mediaID
        self.index = max(index, 0)
    }
}
