import AppKit
import XCTest

final class ImageviewAppUITests: XCTestCase {
    private static let appBundleIdentifier = "com.local.Imageview"
    private var app: XCUIApplication!
    private var appURL: URL!
    private var fixturesURL: URL!
    private var originalDefaults: [String: Any]?

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalDefaults = UserDefaults.standard.persistentDomain(
            forName: Self.appBundleIdentifier
        )
        resetPreferences(language: "en")
        fixturesURL = try makeFixtures()
        appURL = try configuredAppURL()
        app = XCUIApplication(bundleIdentifier: Self.appBundleIdentifier)
        launchApp()
        XCTAssertTrue(app.windows["Imageview"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let fixturesURL {
            try? FileManager.default.removeItem(at: fixturesURL)
        }
        restorePreferences()
    }

    func testOpenFolderAndNavigateNextAndPrevious() {
        XCTAssertTrue(app.windows["blue.png · 1 / 4"].waitForExistence(timeout: 5))

        app.toolbars.buttons["Next"].click()
        XCTAssertTrue(app.windows["green.png · 2 / 4"].waitForExistence(timeout: 5))

        app.toolbars.buttons["Previous"].click()
        XCTAssertTrue(app.windows["blue.png · 1 / 4"].waitForExistence(timeout: 5))
    }

    func testGridRoundTripReturnsToViewer() {
        app.toolbars.buttons["Grid"].click()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5))

        app.collectionViews.firstMatch.cells.element(boundBy: 1).click()
        XCTAssertFalse(app.collectionViews.firstMatch.exists)
    }

    func testCropSaveCreatesExport() {
        let exportURL = fixturesURL.appendingPathComponent("crop-export.png")
        app.toolbars.buttons["Crop"].click()
        let cropWindow = app.windows["Crop"]
        XCTAssertTrue(cropWindow.waitForExistence(timeout: 5))

        cropWindow.buttons["Save As…"].click()
        let savePanel = app.sheets.firstMatch
        XCTAssertTrue(savePanel.waitForExistence(timeout: 5))
        savePanel.textFields.firstMatch.click()
        savePanel.textFields.firstMatch.typeText(exportURL.path)
        savePanel.buttons["Save"].click()

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    }

    func testPinCreatesFloatingImageWindow() {
        app.toolbars.buttons["Pin Image"].click()
        XCTAssertTrue(app.windows["Image Pin"].waitForExistence(timeout: 5))
    }

    func testLanguagePreferencePersistsAcrossLaunches() {
        resetPreferences(language: "zh-Hans")

        app.terminate()
        launchApp()
        app.toolbars.buttons["Crop"].click()
        XCTAssertTrue(app.windows["裁剪"].waitForExistence(timeout: 5))
    }

    func testCorruptImageDoesNotPreventLaterNavigation() {
        app.toolbars.buttons["Next"].click()
        app.toolbars.buttons["Next"].click()
        XCTAssertTrue(app.windows["middle.png · 3 / 4"].waitForExistence(timeout: 5))
        app.toolbars.buttons["Next"].click()
        XCTAssertTrue(app.windows["red.png · 4 / 4"].waitForExistence(timeout: 5))
    }

    private func makeFixtures() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("imageview-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writePNG(named: "blue.png", color: .systemBlue, to: directory)
        try writePNG(named: "green.png", color: .systemGreen, to: directory)
        try writePNG(named: "red.png", color: .systemRed, to: directory)
        try Data("not an image".utf8).write(to: directory.appendingPathComponent("middle.png"))
        return directory
    }

    private func writePNG(named name: String, color: NSColor, to directory: URL) throws {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
        image.unlockFocus()

        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func configuredAppURL() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["IMAGEVIEW_APP_PATH"],
              !path.isEmpty else {
            throw XCTSkip("IMAGEVIEW_APP_PATH must point to dist/Imageview.app")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Imageview app is not built at \(url.path)")
        }
        return url
    }

    private func launchApp() {
        guard let fixturesURL, let appURL else {
            XCTFail("Imageview UI test was not configured")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [fixturesURL],
            withApplicationAt: appURL,
            configuration: configuration
        )
    }

    private func resetPreferences(language: String) {
        UserDefaults.standard.removePersistentDomain(forName: Self.appBundleIdentifier)
        UserDefaults.standard.setPersistentDomain(
            ["preferences.language": language],
            forName: Self.appBundleIdentifier
        )
    }

    private func restorePreferences() {
        UserDefaults.standard.removePersistentDomain(forName: Self.appBundleIdentifier)
        if let originalDefaults {
            UserDefaults.standard.setPersistentDomain(
                originalDefaults,
                forName: Self.appBundleIdentifier
            )
        }
    }
}
