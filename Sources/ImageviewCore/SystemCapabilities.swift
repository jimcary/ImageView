import Foundation

public enum SystemCapabilities {
    public static var ocrAvailable: Bool {
        ocrAvailable(onMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    public static var liveTextAvailable: Bool {
        liveTextAvailable(onMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    public static var subjectExtractionAvailable: Bool {
        subjectExtractionAvailable(
            onMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }

    public static func ocrAvailable(onMajorVersion majorVersion: Int) -> Bool {
        majorVersion >= 12
    }

    public static func liveTextAvailable(onMajorVersion majorVersion: Int) -> Bool {
        majorVersion >= 13
    }

    public static func subjectExtractionAvailable(onMajorVersion majorVersion: Int) -> Bool {
        majorVersion >= 14
    }
}
