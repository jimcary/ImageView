import AppKit
import XCTest

final class ImageviewAppUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixturesURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixturesURL = try makeFixtures()
        app = XCUIApplication(bundleIdentifier: "com.local.Imageview")
        app.launchArguments = [fixturesURL.path]
        app.launch()
        XCTAssertTrue(app.windows["Imageview"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        try FileManager.default.removeItem(at: fixturesURL)
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
        let defaults = UserDefaults(suiteName: "com.local.Imageview")!
        defaults.set("zh-Hans", forKey: "preferences.language")
        defaults.synchronize()

        app.terminate()
        app.launch()
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
}
