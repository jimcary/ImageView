import AppKit
import ImageIO
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
        XCTAssertTrue(app.windows["blue.jpg · 1 / 4"].waitForExistence(timeout: 5))

        app.toolbars.buttons["Next"].click()
        XCTAssertTrue(app.windows["green.png · 2 / 4"].waitForExistence(timeout: 5))

        app.toolbars.buttons["Previous"].click()
        XCTAssertTrue(app.windows["blue.jpg · 1 / 4"].waitForExistence(timeout: 5))
    }

    func testToolbarUsesDeleteAndOmitsRemovedButtons() {
        XCTAssertTrue(app.toolbars.buttons["Delete"].exists)
        XCTAssertFalse(app.toolbars.buttons["Pin Image"].exists)
        XCTAssertFalse(app.toolbars.buttons["Pin Clipboard"].exists)
        XCTAssertFalse(app.toolbars.buttons["Extract Subject"].exists)
    }

    func testDeleteKeyMovesCurrentFixtureToTrashAndSelectsNext() {
        let blueURL = fixturesURL.appendingPathComponent("blue.jpg")
        XCTAssertTrue(app.windows["blue.jpg · 1 / 4"].waitForExistence(timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: blueURL.path))

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])

        XCTAssertTrue(waitForFileRemoval(at: blueURL))
        XCTAssertTrue(app.windows["green.png · 1 / 3"].waitForExistence(timeout: 5))
    }

    func testDeleteHandlesMiddleLastAndOnlyExplicitFiles() {
        let blueURL = fixturesURL.appendingPathComponent("blue.jpg")
        let greenURL = fixturesURL.appendingPathComponent("green.png")
        let redURL = fixturesURL.appendingPathComponent("red.png")
        app.terminate()
        launchApp(opening: [blueURL, greenURL, redURL])
        XCTAssertTrue(app.windows["blue.jpg · 1 / 3"].waitForExistence(timeout: 5))

        app.toolbars.buttons["Next"].click()
        XCTAssertTrue(app.windows["green.png · 2 / 3"].waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForFileRemoval(at: greenURL))
        XCTAssertTrue(app.windows["red.png · 2 / 2"].waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForFileRemoval(at: redURL))
        XCTAssertTrue(app.windows["blue.jpg · 1 / 1"].waitForExistence(timeout: 5))

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForFileRemoval(at: blueURL))
        XCTAssertTrue(app.windows["Imageview"].waitForExistence(timeout: 5))
    }

    func testImageCanvasContextMenuUsesSupportedActions() {
        let blueURL = fixturesURL.appendingPathComponent("blue.jpg")
        let greenURL = fixturesURL.appendingPathComponent("green.png")
        let redURL = fixturesURL.appendingPathComponent("red.png")
        app.terminate()
        launchApp(opening: [blueURL, greenURL, redURL])
        XCTAssertTrue(app.windows["blue.jpg · 1 / 3"].waitForExistence(timeout: 5))

        let canvas = app.otherElements["imageCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.rightClick()

        let contextMenu = app.menus["imageCanvasContextMenu"]
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(contextMenu.menuItems.allElementsBoundByIndex.map { $0.title }, [
            "Recognize Text", "Actual Size", "Fit to Window", "Sort",
            "Image Processing", "Finder Label", "Pin to Desktop",
            "Show in Finder", "Open Default", "Copy", "Delete",
        ])

        let sortItem = contextMenu.menuItems["Sort"]
        sortItem.hover()
        let sortMenu = sortItem.menus.firstMatch
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(sortMenu.menuItems.allElementsBoundByIndex.map { $0.title }, [
            "Name", "Extension", "Created", "Modified",
            "Finder Order", "Random", "Finder Label",
        ])
        sortMenu.menuItems["Extension"].click()

        app.toolbars.buttons["Grid"].click()
        XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, "Extension")
        app.toolbars.buttons["Grid"].click()

        canvas.rightClick()
        let reopenedContextMenu = app.menus["imageCanvasContextMenu"]
        XCTAssertTrue(reopenedContextMenu.waitForExistence(timeout: 5))
        let finderLabelItem = reopenedContextMenu.menuItems["Finder Label"]
        finderLabelItem.hover()
        let finderLabelMenu = finderLabelItem.menus.firstMatch
        XCTAssertTrue(finderLabelMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(finderLabelMenu.menuItems.allElementsBoundByIndex.map { $0.title }, [
            "No Label", "Gray", "Green", "Purple",
            "Blue", "Yellow", "Red", "Orange",
        ])
        finderLabelMenu.menuItems["Green"].click()

        app.toolbars.buttons["Info"].click()
        XCTAssertEqual(app.popUpButtons.firstMatch.value as? String, "Green")
    }

    func testGridRoundTripReturnsToViewer() {
        app.toolbars.buttons["Grid"].click()
        XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5))

        app.collectionViews.firstMatch.cells.element(boundBy: 1).click()
        XCTAssertFalse(app.collectionViews.firstMatch.exists)
    }

    func testCropSelectionAndCommandKOverwriteOriginal() {
        let canvas = app.otherElements["imageCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let originalURL = fixturesURL.appendingPathComponent("blue.jpg")
        guard let originalSize = decodedPixelSize(at: originalURL) else {
            return XCTFail("Expected the JPEG fixture to decode before cropping")
        }
        app.toolbars.buttons["Crop"].click()
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.75))
        start.press(forDuration: 0.1, thenDragTo: end)
        app.typeKey("k", modifierFlags: .command)
        guard let croppedSize = waitForDecodedPixelSize(
            at: originalURL,
            smallerThan: originalSize
        ) else {
            return XCTFail("Expected Command-K to overwrite blue.jpg with a decodable crop")
        }
        XCTAssertLessThan(croppedSize.width, originalSize.width)
        XCTAssertLessThan(croppedSize.height, originalSize.height)
    }

    func testRepeatedCropEntryKeepsTheOriginalRollbackBaseline() {
        let canvas = app.otherElements["imageCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        app.toolbars.buttons["Crop"].click()
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.75))
        start.press(forDuration: 0.1, thenDragTo: end)
        app.toolbars.buttons["Crop"].click()
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        canvas.rightClick()
        app.menuItems["Pin to Desktop"].click()

        let pin = app.windows["Image Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(pin.frame.width, 500)
    }

    func testPinCreatesFloatingImageWindow() {
        let canvas = app.otherElements["imageCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.rightClick()
        app.menuItems["Pin to Desktop"].click()
        XCTAssertTrue(app.windows["Image Pin"].waitForExistence(timeout: 5))
    }

    func testLanguagePreferencePersistsAcrossLaunches() {
        resetPreferences(language: "zh-Hans")

        app.terminate()
        launchApp()
        XCTAssertTrue(app.toolbars.buttons["裁剪"].waitForExistence(timeout: 5))
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
        try writeJPEG(
            named: "blue.jpg",
            color: .systemBlue,
            size: NSSize(width: 800, height: 600),
            to: directory
        )
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

    private func writeJPEG(
        named name: String,
        color: NSColor,
        size: NSSize,
        to directory: URL
    ) throws {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.9]
        )!
        try data.write(to: directory.appendingPathComponent(name))
    }

    private func decodedPixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return CGSize(width: image.width, height: image.height)
    }

    private func waitForDecodedPixelSize(at url: URL, smallerThan original: CGSize) -> CGSize? {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let size = decodedPixelSize(at: url),
               size.width < original.width,
               size.height < original.height {
                return size
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    private func waitForFileRemoval(at url: URL) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if !FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
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
        guard let fixturesURL else {
            XCTFail("Imageview UI test was not configured")
            return
        }
        launchApp(opening: [fixturesURL])
    }

    private func launchApp(opening urls: [URL]) {
        guard let appURL else {
            XCTFail("Imageview UI test was not configured")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            urls,
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
