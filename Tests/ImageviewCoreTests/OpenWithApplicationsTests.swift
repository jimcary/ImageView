import Foundation
import Testing
@testable import ImageviewCore

@Test
func openWithApplicationsAreDeduplicatedExcludedAndSorted() {
    let current = URL(fileURLWithPath: "/Applications/Imageview.app")
    let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
    let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")

    let result = OpenWithApplications.rows(
        from: [preview, chrome, preview, current],
        excluding: current
    ) { url in
        url.deletingPathExtension().lastPathComponent
    }

    #expect(result.map(\.displayName) == ["Google Chrome", "Preview"])
    #expect(result.map(\.url) == [chrome, preview])
}
