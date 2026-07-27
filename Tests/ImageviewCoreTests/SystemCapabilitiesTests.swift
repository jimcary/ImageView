import Testing
@testable import ImageviewCore

@Test
func subjectExtractionIsHiddenBeforeRequiredOS() {
    #expect(!SystemCapabilities.subjectExtractionAvailable(onMajorVersion: 12))
    #expect(!SystemCapabilities.subjectExtractionAvailable(onMajorVersion: 13))
    #expect(SystemCapabilities.subjectExtractionAvailable(onMajorVersion: 14))
}

@Test
func ocrIsAvailableOnMinimumSupportedOS() {
    #expect(SystemCapabilities.ocrAvailable(onMajorVersion: 12))
}

@Test
func liveTextIsHiddenOnMacOS12() {
    #expect(!SystemCapabilities.liveTextAvailable(onMajorVersion: 12))
    #expect(SystemCapabilities.liveTextAvailable(onMajorVersion: 13))
}
