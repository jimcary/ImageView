# Imageview V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a stable, local-only native macOS image viewer named Imageview with browsing, crop/save, pinboard, local intelligence, preferences, and Simplified Chinese/English UI.

**Architecture:** Use a Swift Package that Xcode can open directly, split into a testable `ImageviewCore` library and an AppKit `ImageviewApp` executable. Core types own media indexing, crop geometry, decoding, rendering, export, caching, preferences, and capability checks; AppKit controllers own windows and user interaction. A packaging script assembles the release executable and resources into a locally signed universal `.app`.

**Tech Stack:** Swift 6.1, AppKit, Foundation, ImageIO, Core Image, Core Graphics, Vision, Uniform Type Identifiers, XCTest, Swift Package Manager, macOS 12+

## Global Constraints

- Product name is exactly `Imageview`; bundle identifier is exactly `com.local.Imageview`.
- Deployment target is macOS 12.0; release output contains `x86_64` and `arm64`.
- UI localizations are exactly `zh-Hans` and `en`.
- Core viewer and windows use AppKit; SwiftUI is not required for the first implementation.
- No network client, account, purchase, subscription, telemetry, advertising, or Full Disk Access requirement.
- Use only Apple frameworks until a real fixture proves a format gap that cannot be covered by ImageIO/Core Image.
- Every corrupt image, failed decode, directory mutation, cancelled task, and failed save remains recoverable without terminating the app.
- Overwrite export writes and validates a sibling temporary file before atomic replacement.
- Work on local `main`; do not add a remote or push.

## File Map

- `Package.swift`: defines `ImageviewCore`, `ImageviewApp`, and `ImageviewCoreTests`.
- `Sources/ImageviewCore/MediaTypes.swift`: media kinds, supported extension rules, and `MediaItem`.
- `Sources/ImageviewCore/MediaIndex.swift`: filtering, sorting, stable selection, and navigation.
- `Sources/ImageviewCore/FolderScanner.swift`: scoped directory scan and scan result isolation.
- `Sources/ImageviewCore/EditRecipe.swift`: immutable rotation, flip, and normalized crop model.
- `Sources/ImageviewCore/CropGeometry.swift`: view/image coordinate conversion and aspect-ratio constraints.
- `Sources/ImageviewCore/ImageDecoder.swift`: ImageIO/Core Image decode and page/frame metadata.
- `Sources/ImageviewCore/ImageRenderer.swift`: applies orientation, flips, and crop in source-pixel space.
- `Sources/ImageviewCore/ExportCoordinator.swift`: destination format, metadata policy, verified save, and atomic overwrite.
- `Sources/ImageviewCore/CostCache.swift`: pixel-cost bounded least-recently-used cache.
- `Sources/ImageviewCore/AppPreferences.swift`: typed defaults, shortcuts, and conflict validation.
- `Sources/ImageviewCore/SystemCapabilities.swift`: OCR and subject extraction availability.
- `Sources/ImageviewApp/main.swift`: process entry point.
- `Sources/ImageviewApp/AppDelegate.swift`: application lifecycle, menus, open events, and window policy.
- `Sources/ImageviewApp/ViewerWindowController.swift`: viewer window composition and command routing.
- `Sources/ImageviewApp/ImageCanvasView.swift`: drawing, zoom, pan, drag/drop, and crop overlay.
- `Sources/ImageviewApp/ViewerSession.swift`: async scanning/decoding, cancellation, navigation, and prefetch.
- `Sources/ImageviewApp/ThumbnailStripView.swift`: synchronized thumbnail strip.
- `Sources/ImageviewApp/GridViewController.swift`: directory grid and filter controls.
- `Sources/ImageviewApp/InspectorViewController.swift`: metadata and file actions.
- `Sources/ImageviewApp/CropPanelController.swift`: crop ratios, pixel dimensions, and save/copy actions.
- `Sources/ImageviewApp/PinboardWindowController.swift`: image/text pin windows.
- `Sources/ImageviewApp/OCRController.swift`: local Vision recognition and result presentation.
- `Sources/ImageviewApp/PreferencesWindowController.swift`: localized settings and shortcut conflicts.
- `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`: English UI strings.
- `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`: Simplified Chinese UI strings.
- `Tests/ImageviewCoreTests/*.swift`: deterministic unit and integration tests using temporary directories.
- `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`: UI automation source for execution when full Xcode is available.
- `scripts/build-app.sh`: release build, universal merge, bundle assembly, and local ad-hoc signing.
- `scripts/smoke-test.sh`: bundle structure, architecture, localization, and launch smoke checks.
- `Info.plist`: bundle metadata, document types, privacy copy, and minimum system version.

---

### Task 1: Bootstrap the Native Application and Test Harness

**Files:**
- Create: `Package.swift`
- Create: `Sources/ImageviewCore/MediaTypes.swift`
- Create: `Sources/ImageviewApp/main.swift`
- Create: `Sources/ImageviewApp/AppDelegate.swift`
- Create: `Info.plist`
- Create: `Tests/ImageviewCoreTests/MediaTypeRegistryTests.swift`

**Interfaces:**
- Produces: `MediaKind`, `MediaTypeRegistry.isSupported(url:) -> Bool`, and the `ImageviewApp` executable.

- [ ] **Step 1: Write the failing registry test**

```swift
func testSupportedExtensionsAreCaseInsensitiveAndRejectUnknownFiles() {
    XCTAssertTrue(MediaTypeRegistry.isSupported(url: URL(fileURLWithPath: "/tmp/A.JPEG")))
    XCTAssertTrue(MediaTypeRegistry.isSupported(url: URL(fileURLWithPath: "/tmp/a.heic")))
    XCTAssertFalse(MediaTypeRegistry.isSupported(url: URL(fileURLWithPath: "/tmp/a.txt")))
}
```

- [ ] **Step 2: Run the test and verify the missing module/type failure**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter MediaTypeRegistryTests`

Expected: FAIL because `ImageviewCore` or `MediaTypeRegistry` is not defined.

- [ ] **Step 3: Add the package, minimal registry, and AppKit entry point**

```swift
public enum MediaTypeRegistry {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp", "heic", "heif",
        "pdf", "eps", "ico", "icns", "psd", "webp", "avif", "dng", "raw"
    ]

    public static func isSupported(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
```

The executable calls `NSApplication.shared.run()` with `AppDelegate` retained for the process lifetime. `Info.plist` sets `CFBundleName`, `CFBundleIdentifier`, `LSMinimumSystemVersion`, and image/PDF document types.

- [ ] **Step 4: Run the registry test and debug executable build**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter MediaTypeRegistryTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift build --product Imageview`

Expected: exit 0 and `.build/debug/Imageview` exists.

- [ ] **Step 5: Commit the bootstrap**

```bash
git add Package.swift Info.plist Sources Tests/ImageviewCoreTests/MediaTypeRegistryTests.swift
git commit -m "chore: bootstrap Imageview macOS app"
```

### Task 2: Scan Directories and Keep Navigation Stable

**Files:**
- Modify: `Sources/ImageviewCore/MediaTypes.swift`
- Create: `Sources/ImageviewCore/FolderScanner.swift`
- Create: `Sources/ImageviewCore/MediaIndex.swift`
- Create: `Tests/ImageviewCoreTests/FolderScannerTests.swift`
- Create: `Tests/ImageviewCoreTests/MediaIndexTests.swift`

**Interfaces:**
- Consumes: `MediaTypeRegistry.isSupported(url:)`.
- Produces: `MediaItem.init(url:resourceIdentifier:fileSize:createdAt:modifiedAt:finderLabel:)`; `FolderScanner.scan(folder:recursive:) throws -> [MediaItem]`; `MediaIndex.replaceItems(_:preserving:)`; `MediaIndex.move(_:) -> MediaItem?`.

- [ ] **Step 1: Write failing scan and selection tests**

```swift
func testScannerIncludesImagesAndSkipsUnsupportedFiles() throws {
    let folder = try TemporaryFolder(files: ["b.png": Data(), "a.JPG": Data(), "note.txt": Data()])
    let result = try FolderScanner().scan(folder: folder.url, recursive: false)
    XCTAssertEqual(result.map(\.url.lastPathComponent).sorted(), ["a.JPG", "b.png"])
}

func testReplacingItemsPreservesCurrentResourceIdentifier() {
    var index = MediaIndex(items: fixtures(["a.jpg", "b.jpg", "c.jpg"]))
    index.select(id: index.items[1].id)
    index.replaceItems([index.items[2], index.items[1]])
    XCTAssertEqual(index.current?.url.lastPathComponent, "b.jpg")
}
```

- [ ] **Step 2: Run the focused tests**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter FolderScannerTests`

Expected: FAIL because `FolderScanner` is undefined.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter MediaIndexTests`

Expected: FAIL because `MediaIndex` is undefined.

- [ ] **Step 3: Implement one-pass scanning and stable navigation**

`FolderScanner` reads resource keys in one enumeration, catches errors per URL, excludes hidden/package descendants, and returns valid `MediaItem` values without force unwraps. `MediaIndex` stores the selected stable ID, supports name/extension/creation/modification/Finder-order/random/label sorting, and chooses the nearest surviving item after deletion.

- [ ] **Step 4: Run both focused suites**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter FolderScannerTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter MediaIndexTests`

Expected: PASS, including empty-list and deletion-neighbor cases.

- [ ] **Step 5: Commit media indexing**

```bash
git add Sources/ImageviewCore/MediaTypes.swift Sources/ImageviewCore/FolderScanner.swift Sources/ImageviewCore/MediaIndex.swift Tests/ImageviewCoreTests
git commit -m "feat: add stable folder media index"
```

### Task 3: Model Crop, Rotation, and Flip Geometry

**Files:**
- Create: `Sources/ImageviewCore/EditRecipe.swift`
- Create: `Sources/ImageviewCore/CropGeometry.swift`
- Create: `Tests/ImageviewCoreTests/CropGeometryTests.swift`
- Create: `Tests/ImageviewCoreTests/EditRecipeTests.swift`

**Interfaces:**
- Produces: `EditRecipe(rotationQuarterTurns:flipHorizontal:flipVertical:crop:)`; `NormalizedRect`; `CropAspect`; `CropGeometry.pixelRect(imageSize:) -> CGRect`; `CropGeometry.constrain(_:to:inside:) -> CGRect`.

- [ ] **Step 1: Write failing coordinate and composition tests**

```swift
func testNormalizedCropConvertsToIntegralSourcePixels() {
    let crop = NormalizedRect(x: 0.25, y: 0.10, width: 0.50, height: 0.40)
    XCTAssertEqual(CropGeometry(crop: crop).pixelRect(imageSize: CGSize(width: 4000, height: 3000)),
                   CGRect(x: 1000, y: 300, width: 2000, height: 1200))
}

func testQuarterTurnsNormalizeAndFlipsRemainIndependent() {
    let recipe = EditRecipe(rotationQuarterTurns: 5, flipHorizontal: true, flipVertical: false, crop: .full)
    XCTAssertEqual(recipe.rotationQuarterTurns, 1)
    XCTAssertTrue(recipe.flipHorizontal)
}
```

- [ ] **Step 2: Run the focused tests**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter CropGeometryTests`

Expected: FAIL because crop types are undefined.

- [ ] **Step 3: Implement immutable edit values and clamped geometry**

All normalized coordinates clamp to `0...1`; width and height remain positive; pixel conversion uses integral rectangles bounded by source dimensions. Ratios include free, original, 1:1, 1:2, 2:1, 2:3, 3:2, 3:4, 4:3, 9:16, and 16:9.

- [ ] **Step 4: Run edit suites**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter CropGeometryTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter EditRecipeTests`

Expected: PASS.

- [ ] **Step 5: Commit edit geometry**

```bash
git add Sources/ImageviewCore/EditRecipe.swift Sources/ImageviewCore/CropGeometry.swift Tests/ImageviewCoreTests
git commit -m "feat: add crop and transform geometry"
```

### Task 4: Decode, Render, and Verify Saved Images

**Files:**
- Create: `Sources/ImageviewCore/ImageDecoder.swift`
- Create: `Sources/ImageviewCore/ImageRenderer.swift`
- Create: `Sources/ImageviewCore/ExportCoordinator.swift`
- Create: `Tests/ImageviewCoreTests/ImagePipelineTests.swift`
- Create: `Tests/ImageviewCoreTests/ExportCoordinatorTests.swift`

**Interfaces:**
- Consumes: `MediaItem`, `EditRecipe`, and `CropGeometry`.
- Produces: `DecodedImage`; `ImageDecoder.decode(url:page:) throws -> DecodedImage`; `ImageRenderer.render(_:recipe:) throws -> CGImage`; `ExportCoordinator.save(image:sourceProperties:request:) throws -> URL`.

- [ ] **Step 1: Write failing real-pixel pipeline tests**

```swift
func testRendererCropsAndRotatesRealPixels() throws {
    let source = try FixtureImage.quadrants(width: 40, height: 20)
    let recipe = EditRecipe(rotationQuarterTurns: 1, crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1))
    let rendered = try ImageRenderer().render(source, recipe: recipe)
    XCTAssertEqual(rendered.width, 20)
    XCTAssertEqual(rendered.height, 20)
}

func testFailedOverwriteLeavesOriginalBytesUntouched() throws {
    let original = try FixtureImage.writeJPEG()
    let bytes = try Data(contentsOf: original)
    let coordinator = ExportCoordinator(validator: { _ in false })
    XCTAssertThrowsError(try coordinator.overwrite(image: FixtureImage.cgImage, originalURL: original, format: .jpeg(quality: 0.8)))
    XCTAssertEqual(try Data(contentsOf: original), bytes)
}
```

- [ ] **Step 2: Run pipeline suites**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter ImagePipelineTests`

Expected: FAIL because `ImageRenderer` is undefined.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter ExportCoordinatorTests`

Expected: FAIL because `ExportCoordinator` is undefined.

- [ ] **Step 3: Implement ImageIO decode, Core Graphics rendering, and transactional export**

Decode honors EXIF orientation, page count, animation duration, embedded color space, and metadata dictionaries. Rendering uses a bitmap context sized from the final crop and quarter-turn transform. Export writes a unique sibling temporary URL, finalizes `CGImageDestination`, reopens the result with ImageIO, verifies non-zero dimensions, then moves for save-as or calls `FileManager.replaceItemAt` for overwrite. Every failure removes only the temporary file.

- [ ] **Step 4: Run pipeline and export suites**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter ImagePipelineTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter ExportCoordinatorTests`

Expected: PASS for JPEG/PNG/TIFF, metadata keep/remove, target-exists, and injected validation failure.

- [ ] **Step 5: Commit the safe editing pipeline**

```bash
git add Sources/ImageviewCore/ImageDecoder.swift Sources/ImageviewCore/ImageRenderer.swift Sources/ImageviewCore/ExportCoordinator.swift Tests/ImageviewCoreTests
git commit -m "feat: add verified crop export pipeline"
```

### Task 5: Build the Viewer Window and Cancellable Session

**Files:**
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Create: `Sources/ImageviewApp/ViewerWindowController.swift`
- Create: `Sources/ImageviewApp/ImageCanvasView.swift`
- Create: `Sources/ImageviewApp/ViewerSession.swift`
- Create: `Sources/ImageviewCore/CostCache.swift`
- Create: `Tests/ImageviewCoreTests/CostCacheTests.swift`
- Create: `Tests/ImageviewCoreTests/DecodeCancellationTests.swift`

**Interfaces:**
- Consumes: `FolderScanner`, `MediaIndex`, `ImageDecoder`, and `EditRecipe`.
- Produces: `ViewerSession.open(urls:)`, `ViewerSession.open(folder:)`, `ViewerSession.move(_:)`, `ViewerSession.currentFrame`; `CostCache<Key, Value>.insert(_:for:cost:)`.

- [ ] **Step 1: Write failing cache and cancellation tests**

```swift
func testCacheEvictsLeastRecentlyUsedNonCurrentEntryByPixelCost() {
    var cache = CostCache<String, Int>(costLimit: 10)
    cache.insert(1, for: "current", cost: 6, protected: true)
    cache.insert(2, for: "old", cost: 4)
    cache.insert(3, for: "new", cost: 4)
    XCTAssertNil(cache.value(for: "old"))
    XCTAssertEqual(cache.value(for: "current"), 1)
}
```

The cancellation test injects a decoder whose first request suspends and whose second request completes; it asserts that only the second frame is published.

- [ ] **Step 2: Run focused tests**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter CostCacheTests`

Expected: FAIL because `CostCache` is undefined.

- [ ] **Step 3: Implement viewer session, canvas, and commands**

The window shows a dark canvas, title `filename · index / count`, open controls, previous/next navigation, zoom modes, rotation, flip, crop, grid, inspector, and pin commands. `ViewerSession` uses a generation token plus cancelled `Task` handles so stale decoding cannot replace the current image. Prefetch is limited to two items on each side, and memory-pressure handling clears unprotected frames.

- [ ] **Step 4: Verify focused tests and launch**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter CostCacheTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter DecodeCancellationTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift run Imageview`

Expected: Imageview opens an empty viewer window; closing the window does not crash the process.

- [ ] **Step 5: Commit the viewer milestone**

```bash
git add Sources/ImageviewApp Sources/ImageviewCore/CostCache.swift Tests/ImageviewCoreTests
git commit -m "feat: add cancellable image viewer"
```

### Task 6: Connect Interactive Crop, Copy, Save As, and Overwrite

**Files:**
- Modify: `Sources/ImageviewApp/ImageCanvasView.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Sources/ImageviewApp/ViewerSession.swift`
- Create: `Sources/ImageviewApp/CropPanelController.swift`
- Create: `Tests/ImageviewCoreTests/CropSaveWorkflowTests.swift`

**Interfaces:**
- Consumes: `EditRecipe`, `CropGeometry`, `ImageRenderer`, and `ExportCoordinator`.
- Produces: `ImageCanvasView.editRecipe`; `CropPanelController.begin(for:)`; `ViewerSession.export(_:)`; `ViewerSession.overwriteCurrent()`.

- [ ] **Step 1: Write the failing end-to-end crop-save core test**

```swift
func testCropSaveCanBeDecodedAndHasRequestedDimensions() throws {
    let sourceURL = try FixtureImage.writePNG(width: 120, height: 80)
    let outputURL = temporaryURL("crop.png")
    let recipe = EditRecipe(crop: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    try CropSaveWorkflow().save(sourceURL: sourceURL, recipe: recipe, destinationURL: outputURL)
    let decoded = try ImageDecoder().decode(url: outputURL)
    XCTAssertEqual(decoded.pixelSize, CGSize(width: 60, height: 40))
}
```

- [ ] **Step 2: Run the crop-save test**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter CropSaveWorkflowTests`

Expected: FAIL because `CropSaveWorkflow` is undefined.

- [ ] **Step 3: Implement crop UI and safe save commands**

The canvas draws draggable handles and thirds guides in image coordinates. The panel exposes all specified ratios plus integer pixel width/height. Copy renders to `NSPasteboard`; Save As uses `NSSavePanel`; Overwrite presents one confirmation and then calls verified atomic export. Export errors stay in the viewer and show a localized recovery message.

- [ ] **Step 4: Run the crop-save test and manual workflow**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter CropSaveWorkflowTests`

Expected: PASS.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift run Imageview /private/tmp/imageview-crop-fixture.png`

Expected: crop handles move, the saved image reopens, and cancelling the save panel changes no file.

- [ ] **Step 5: Commit working crop/save**

```bash
git add Sources/ImageviewApp Sources/ImageviewCore Tests/ImageviewCoreTests/CropSaveWorkflowTests.swift
git commit -m "feat: enable reliable crop and save"
```

### Task 7: Add Thumbnails, Grid, Inspector, and File Operations

**Files:**
- Create: `Sources/ImageviewApp/ThumbnailStripView.swift`
- Create: `Sources/ImageviewApp/GridViewController.swift`
- Create: `Sources/ImageviewApp/InspectorViewController.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Sources/ImageviewApp/ViewerSession.swift`
- Create: `Tests/ImageviewCoreTests/MetadataAndLabelsTests.swift`

**Interfaces:**
- Consumes: `MediaIndex`, `DecodedImage.properties`, and `ViewerSession`.
- Produces: synchronized thumbnail/grid selection; inspector metadata rows; Finder reveal, path copy, default-open, label set/clear, print, and `FileManager.trashItem` actions.

- [ ] **Step 1: Write failing metadata and label tests**

```swift
func testInspectorFlattensExifWithoutLosingDisplayedKeys() {
    let rows = MetadataFormatter.rows(from: ["{Exif}": ["FNumber": 2.8], "PixelWidth": 6000])
    XCTAssertTrue(rows.contains(.init(key: "EXIF.FNumber", value: "2.8")))
    XCTAssertTrue(rows.contains(.init(key: "PixelWidth", value: "6000")))
}
```

- [ ] **Step 2: Run metadata tests**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter MetadataAndLabelsTests`

Expected: FAIL because `MetadataFormatter` is undefined.

- [ ] **Step 3: Implement synchronized collection views and native file actions**

Thumbnail and grid cells request low-priority thumbnails and reuse views. Selecting either view selects the same `MediaItem.ID`. Inspector reads dimensions, size, format, color space, dates, camera/exposure, EXIF, and IPTC. Trash uses the system trash API; Finder labels use URL resource values; reveal and default-open use `NSWorkspace`.

- [ ] **Step 4: Run tests and browse a mixed temporary directory**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter MetadataAndLabelsTests`

Expected: PASS.

Manual check: open a directory containing supported and corrupt fixtures, switch grid/viewer repeatedly, and verify a corrupt selection shows an error while next/previous remains usable.

- [ ] **Step 5: Commit library browsing UI**

```bash
git add Sources/ImageviewApp Sources/ImageviewCore Tests/ImageviewCoreTests/MetadataAndLabelsTests.swift
git commit -m "feat: add grid thumbnails and inspector"
```

### Task 8: Add Pinboard, Clipboard, OCR, and Capability-Gated Features

**Files:**
- Create: `Sources/ImageviewApp/PinboardWindowController.swift`
- Create: `Sources/ImageviewApp/OCRController.swift`
- Create: `Sources/ImageviewCore/SystemCapabilities.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Create: `Tests/ImageviewCoreTests/SystemCapabilitiesTests.swift`

**Interfaces:**
- Consumes: current rendered image and `NSPasteboard`.
- Produces: image/text pin windows; `OCRController.recognize(_:completion:)`; `SystemCapabilities.ocrAvailable`; `SystemCapabilities.subjectExtractionAvailable`.

- [ ] **Step 1: Write failing OS capability tests**

```swift
func testSubjectExtractionIsHiddenBeforeItsRequiredOS() {
    XCTAssertFalse(SystemCapabilities.subjectExtractionAvailable(onMajorVersion: 12))
}

func testOCRIsAvailableOnMinimumSupportedOS() {
    XCTAssertTrue(SystemCapabilities.ocrAvailable(onMajorVersion: 12))
}
```

- [ ] **Step 2: Run capability tests**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter SystemCapabilitiesTests`

Expected: FAIL because `SystemCapabilities` is undefined.

- [ ] **Step 3: Implement pin windows and local Vision OCR**

Pin windows are borderless, draggable, floating, resizable, and expose opacity/original-size/thumbnail/close commands. Clipboard image and text each create the matching pin type. OCR uses `VNRecognizeTextRequest` off the main thread and returns ordered text. Unsupported subject extraction and live-text controls are omitted from menus and toolbars instead of disabled.

- [ ] **Step 4: Run capability tests and manual clipboard/OCR checks**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter SystemCapabilitiesTests`

Expected: PASS.

Manual check: copy an image and text into the pasteboard, create both pin types, adjust opacity, and run OCR on an English/Chinese fixture without network activity.

- [ ] **Step 5: Commit pinboard and intelligence**

```bash
git add Sources/ImageviewApp Sources/ImageviewCore/SystemCapabilities.swift Tests/ImageviewCoreTests/SystemCapabilitiesTests.swift
git commit -m "feat: add pinboard and local OCR"
```

### Task 9: Add Preferences, Shortcuts, and Two Localizations

**Files:**
- Create: `Sources/ImageviewCore/AppPreferences.swift`
- Create: `Sources/ImageviewApp/PreferencesWindowController.swift`
- Create: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Create: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Create: `Tests/ImageviewCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Produces: `AppPreferences`; `Shortcut`; `ShortcutValidator.conflicts(in:) -> [ShortcutConflict]`; `AppLanguage.system/en/zhHans`; `L10n.text(_:)`.

- [ ] **Step 1: Write failing persistence and conflict tests**

```swift
func testDuplicateShortcutReportsBothCommands() {
    let shortcuts = [
        Shortcut(command: .next, key: "j", modifiers: []),
        Shortcut(command: .previous, key: "j", modifiers: [])
    ]
    XCTAssertEqual(ShortcutValidator.conflicts(in: shortcuts).count, 1)
}

func testResetRestoresDocumentedDefaults() {
    let store = InMemoryPreferences()
    store.thumbnailSize = 300
    store.reset()
    XCTAssertEqual(store.thumbnailSize, AppPreferences.defaultThumbnailSize)
}
```

- [ ] **Step 2: Run preference tests**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter AppPreferencesTests`

Expected: FAIL because preference types are undefined.

- [ ] **Step 3: Implement settings tabs, runtime language, and localized public commands**

The settings window contains General, Viewer, Thumbnails, Pinboard, Shortcuts, Formats, and Advanced sections. Values use `UserDefaults` with typed defaults. Language selection rebuilds menus and newly opened windows without changing system settings. Shortcut edits reject conflicts before persistence and support reset.

- [ ] **Step 4: Run preference tests and localization audit**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter AppPreferencesTests`

Expected: PASS.

Run: `rg 'NSLocalizedString|L10n\\.text' Sources/ImageviewApp -n`

Expected: all public menu, toolbar, alert, empty-state, inspector, crop, pinboard, and preference strings use localization keys present in both `.strings` files.

- [ ] **Step 5: Commit preferences and languages**

```bash
git add Sources/ImageviewCore/AppPreferences.swift Sources/ImageviewApp Tests/ImageviewCoreTests/AppPreferencesTests.swift
git commit -m "feat: add bilingual preferences and shortcuts"
```

### Task 10: Add Directory Monitoring and Stability Regression Coverage

**Files:**
- Modify: `Sources/ImageviewCore/FolderScanner.swift`
- Create: `Sources/ImageviewCore/FolderMonitor.swift`
- Modify: `Sources/ImageviewApp/ViewerSession.swift`
- Create: `Tests/ImageviewCoreTests/FolderMonitorTests.swift`
- Create: `Tests/ImageviewCoreTests/StabilityRegressionTests.swift`

**Interfaces:**
- Produces: `FolderMonitor.start(url:onChange:)`; `FolderMonitor.stop()`; debounced rescan events consumed by `ViewerSession`.

- [ ] **Step 1: Write failing directory-mutation and corrupt-file regressions**

```swift
func testDeletingCurrentItemSelectsNearestSurvivor() {
    var index = MediaIndex(items: fixtures(["a.jpg", "b.jpg", "c.jpg"]))
    index.select(id: index.items[1].id)
    index.replaceItems([index.items[0], index.items[2]])
    XCTAssertEqual(index.current?.url.lastPathComponent, "c.jpg")
}

func testCorruptImageFailureDoesNotPreventNextDecode() async throws {
    let session = TestDecodeSession(results: [.failure(.corrupt), .success(FixtureImage.decoded)])
    await session.move(.next)
    XCTAssertNotNil(await session.currentFrame)
}
```

- [ ] **Step 2: Run stability suites**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test --filter StabilityRegressionTests`

Expected: FAIL until the error-isolation path and nearest-survivor rule are complete.

- [ ] **Step 3: Implement debounced monitoring and lifecycle cancellation**

Monitor directory file-descriptor events, debounce bursts into one rescan, preserve selection by resource identifier, and stop on window close. Decode/export/OCR errors become typed user-facing state. Session collections validate indices after every replacement, and no mutable file-list access uses force unwrap.

- [ ] **Step 4: Run the entire automated suite**

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test`

Expected: all tests pass with zero unexpected failures.

- [ ] **Step 5: Commit stability hardening**

```bash
git add Sources Tests
git commit -m "fix: isolate file and decode failures"
```

### Task 11: Package, Inspect, and Smoke-Test the Local App

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/smoke-test.sh`
- Create: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Consumes: `Imageview` release executable, `Info.plist`, and `.lproj` resources.
- Produces: `dist/Imageview.app` containing both requested architectures when both release builds succeed.

- [ ] **Step 1: Write the failing bundle smoke checks**

```bash
test -x dist/Imageview.app/Contents/MacOS/Imageview
test -f dist/Imageview.app/Contents/Info.plist
test -f dist/Imageview.app/Contents/Resources/en.lproj/Localizable.strings
test -f dist/Imageview.app/Contents/Resources/zh-Hans.lproj/Localizable.strings
lipo -verify_arch x86_64 arm64 dist/Imageview.app/Contents/MacOS/Imageview
codesign --verify --deep --strict dist/Imageview.app
```

- [ ] **Step 2: Run the smoke script before the bundle exists**

Run: `./scripts/smoke-test.sh`

Expected: FAIL because `dist/Imageview.app` does not exist.

- [ ] **Step 3: Implement deterministic local packaging**

`build-app.sh` builds release once for `x86_64-apple-macosx` and once for `arm64-apple-macosx`, merges executables with `lipo`, copies the exact `Info.plist` and localization files, applies ad-hoc signing, and never writes outside the repository except Swift/Clang caches under `/private/tmp`.

README documents launch, open-file/folder, crop save, keyboard navigation, language selection, minimum system, local-only privacy, and the absence of online licensing. UI test source covers open, next/previous, grid round-trip, crop save, pin creation, preference persistence, and corrupt-image continuation; it is run after full Xcode is installed.

- [ ] **Step 4: Build and verify the app**

Run: `./scripts/build-app.sh`

Expected: exit 0 and `dist/Imageview.app` exists.

Run: `./scripts/smoke-test.sh`

Expected: bundle, architecture, localization, signature, and launch checks pass.

Run: `CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache swift test`

Expected: all automated tests pass.

- [ ] **Step 5: Commit the local V1 checkpoint**

```bash
git add .gitignore README.md Info.plist Package.swift Sources Tests scripts docs
git commit -m "feat: deliver Imageview local v1"
```

## Spec Coverage Review

- Product identity, OS floor, architectures, local-only privacy, and languages: global constraints plus Tasks 1, 9, and 11.
- Open files/folders, drag/drop, navigation, sorting, filtering, single/multi-window behavior: Tasks 2, 5, 7, and 9.
- Crop, rotation, flips, copy, save-as, safe overwrite, formats, quality, metadata: Tasks 3, 4, and 6.
- Grid, thumbnails, metadata, labels, Finder actions, trash, and print: Task 7.
- Pinboard, clipboard, OCR, live-text/subject capability gating: Task 8.
- Preferences and configurable shortcuts: Task 9.
- Directory changes, removable-volume failure, corrupt media, cancellation, memory limits, and crash regressions: Tasks 5 and 10.
- Universal local app, signing, localization resources, documentation, smoke tests, and UI automation source: Task 11.

