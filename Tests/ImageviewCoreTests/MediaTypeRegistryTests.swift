import Foundation
import Testing
@testable import ImageviewCore

@Test
func supportedExtensionsAreCaseInsensitive() {
    #expect(MediaTypeRegistry.isSupported(url: URL(fileURLWithPath: "/tmp/A.JPEG")))
}

@Test
func supportedImageExtensionIsAccepted() {
    #expect(MediaTypeRegistry.isSupported(url: URL(fileURLWithPath: "/tmp/a.heic")))
}

@Test
func unknownExtensionIsRejected() {
    #expect(!MediaTypeRegistry.isSupported(url: URL(fileURLWithPath: "/tmp/a.txt")))
}
