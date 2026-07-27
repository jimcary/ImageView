# Imageview Direct Crop and Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a local Imageview test build with a reduced toolbar, recoverable Delete command, direct on-canvas crop committed by `⌘K`, a Picview-structured context menu containing only supported commands, and the supplied `Imageview.icns` app icon.

**Architecture:** Keep command routing in `ViewerWindowController` and `AppDelegate`, while `ViewerSession` owns current-media mutations and `MediaIndex` owns post-removal selection. Extend the existing `ImageCanvasView` crop state instead of adding another overlay component, and reuse the current renderer/export coordinator for validated atomic overwrite. Build the context menu from existing viewer commands, with no placeholder actions or new dependencies.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, ImageIO, Swift Testing, XCTest UI tests, Swift Package Manager, shell packaging scripts.

## Global Constraints

- Minimum system remains macOS 12.0.
- The app remains universal: `x86_64` and `arm64`.
- UI text is English and Simplified Chinese only.
- Delete always uses the macOS Trash and is recoverable.
- `⌘K` directly overwrites only JPEG, PNG, TIFF, HEIC, and HEIF through the existing temporary-file validation and atomic replacement path.
- The Picview-inspired context menu contains only Imageview commands that work now; it has no disabled placeholders.
- Do not add dependencies, networking, telemetry, licensing, or Full Disk Access.
- Work on local `main`; do not create a branch or push a remote.

---

### Task 1: Core removal selection and shortcut contracts

**Files:**
- Modify: `Sources/ImageviewCore/MediaIndex.swift`
- Modify: `Sources/ImageviewCore/AppPreferences.swift`
- Modify: `Sources/ImageviewApp/PreferencesWindowController.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/ImageviewCoreTests/MediaIndexTests.swift`
- Test: `Tests/ImageviewCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Produces: `MediaIndex.removeCurrent() -> MediaItem?`
- Produces: `ShortcutCommand.delete`
- Produces: crop default `Shortcut(command: .crop, key: "k", modifiers: [.command])`
- Produces: delete default `Shortcut(command: .delete, key: "\u{7F}", modifiers: [])`
- Consumes: existing `MediaIndex.current`, `Shortcut`, and shortcut persistence validation.

- [ ] **Step 1: Add failing removal-selection tests**

Append behavior tests with literal expected filenames:

```swift
@Test
func removingMiddleItemSelectsTheFollowingItem() {
    let items = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: items)
    index.select(id: items[1].id)

    let removed = index.removeCurrent()

    #expect(removed?.url.lastPathComponent == "b.jpg")
    #expect(index.current?.url.lastPathComponent == "c.jpg")
}

@Test
func removingLastItemSelectsThePreviousItem() {
    let items = mediaFixtures(["a.jpg", "b.jpg"])
    var index = MediaIndex(items: items)
    index.select(id: items[1].id)

    _ = index.removeCurrent()

    #expect(index.current?.url.lastPathComponent == "a.jpg")
}
```

- [ ] **Step 2: Add a failing shortcut-default test**

```swift
@Test
func cropAndDeleteUseTheRequestedDefaultShortcuts() {
    #expect(
        AppPreferences.defaultShortcut(for: .crop)
            == Shortcut(command: .crop, key: "k", modifiers: [.command])
    )
    #expect(
        AppPreferences.defaultShortcut(for: .delete)
            == Shortcut(command: .delete, key: "\u{7F}", modifiers: [])
    )
}
```

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/imageview-swiftpm-cache \
swift test --scratch-path /private/tmp/imageview-task1-red \
  --filter 'removing|cropAndDelete'
```

Expected: compilation fails because `removeCurrent()` and `.delete` do not exist, and the existing crop shortcut is not `⌘K`.

- [ ] **Step 4: Implement the minimal core behavior**

Add `.delete` to `ShortcutCommand`, change `.crop`, and add:

```swift
@discardableResult
public mutating func removeCurrent() -> MediaItem? {
    guard let currentIndex, items.indices.contains(currentIndex) else {
        return nil
    }
    let removed = items.remove(at: currentIndex)
    self.currentIndex = items.isEmpty ? nil : min(currentIndex, items.count - 1)
    return removed
}
```

Map `"\u{7F}"` to the visible key `⌫` and back in `PreferencesWindowController`. Add `shortcut.delete` in both localization files and update the shortcut summary text to show `⌘K` and `⌫`.

- [ ] **Step 5: Run focused and full core tests**

Run the focused command from Step 3, then:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/imageview-swiftpm-cache \
swift test --scratch-path /private/tmp/imageview-task1-green
```

Expected: all tests pass with no failures.

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/ImageviewCore/MediaIndex.swift \
  Sources/ImageviewCore/AppPreferences.swift \
  Sources/ImageviewApp/PreferencesWindowController.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/MediaIndexTests.swift \
  Tests/ImageviewCoreTests/AppPreferencesTests.swift
git commit -m "feat: add crop and delete shortcut contracts"
```

---

### Task 2: Direct on-canvas crop and atomic `⌘K` overwrite

**Files:**
- Modify: `Sources/ImageviewCore/CropGeometry.swift`
- Modify: `Sources/ImageviewApp/ImageCanvasView.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Delete: `Sources/ImageviewApp/CropPanelController.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/ImageviewCoreTests/CropGeometryTests.swift`
- Modify: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`

**Interfaces:**
- Produces: `CropGeometry.normalizedSelection(from:to:inside:) -> NormalizedRect?`
- Produces: `ImageCanvasView.hasCropSelection: Bool`
- Produces callbacks: `ImageCanvasView.onCancelCrop: (() -> Void)?`
- Produces commands: `ViewerWindowController.commitCropAndOverwrite(_:)` and `cancelCrop(_:)`
- Consumes: `ViewerSession.setCrop`, `ViewerSession.overwriteCurrent`, `ExportFormat`, `MetadataPolicy.preserve`.

- [ ] **Step 1: Add a failing crop-selection geometry test**

Use hand-calculated coordinates:

```swift
@Test
func dragPointsProduceAClampedNormalizedSelection() throws {
    let selection = try #require(
        CropGeometry.normalizedSelection(
            from: CGPoint(x: 30, y: 10),
            to: CGPoint(x: 130, y: 90),
            inside: CGRect(x: 10, y: 10, width: 100, height: 50)
        )
    )

    #expect(selection == NormalizedRect(x: 0.2, y: 0, width: 0.8, height: 1))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/imageview-swiftpm-cache \
swift test --scratch-path /private/tmp/imageview-task2-red \
  --filter dragPointsProduceAClampedNormalizedSelection
```

Expected: compilation fails because `normalizedSelection` does not exist.

- [ ] **Step 3: Implement normalized drag conversion**

Add a static helper that intersects both drag points with `bounds`, standardizes the rectangle, returns `nil` for empty bounds or a selection smaller than one display point, and converts the result to `NormalizedRect` using literal bounds-relative division.

- [ ] **Step 4: Replace panel-driven crop state in the canvas**

Keep normal pan behavior unchanged. In crop mode:

```swift
func beginCrop() {
    cropMode = true
    hasCropSelection = false
    cropDrag = nil
    window?.makeFirstResponder(self)
    needsDisplay = true
}
```

On the first mouse drag inside the rendered image, use
`CropGeometry.normalizedSelection` to create the crop. After a selection exists,
retain the existing edge, corner, and interior-move handling. Add
`onCancelCrop` and route `cancelOperation(_:)` to it. Only draw the overlay when
`hasCropSelection` is true.

- [ ] **Step 5: Route crop commands without the floating panel**

In `ViewerWindowController`:

- Remove `cropPanel` and all panel callbacks/helpers.
- `beginCrop(_:)` records `cropBeforeEditing` and calls `canvas.beginCrop()`.
- `commitCropAndOverwrite(_:)` requires crop mode and a valid selection, derives
  the original format with quality `0.9`, calls
  `session.overwriteCurrent(format:metadataPolicy: .preserve)`, and exits crop
  only after success.
- Unsupported formats show the existing localized overwrite error and keep the
  selection active.
- `cancelCrop(_:)` restores `cropBeforeEditing` and exits crop.
- Connect `canvas.onCancelCrop` to `cancelCrop(_:)`.

Delete `CropPanelController.swift` after all references are removed.

- [ ] **Step 6: Bind the Edit menu crop command to `⌘K` commit**

Change the AppDelegate command target from `beginCrop(_:)` to
`commitCropAndOverwrite(_:)`, and use a new localized `menu.crop_and_save`
title. The toolbar and right-click “Crop” remain the entry points.

- [ ] **Step 7: Update the UI crop test**

Replace the save-panel test with a temporary JPEG fixture workflow:

```swift
func testCropSelectionAndCommandKOverwriteOriginal() {
    let canvas = app.otherElements["imageCanvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    app.toolbars.buttons["Crop"].click()
    canvas.press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.75)))
    app.typeKey("k", modifierFlags: .command)
    XCTAssertFalse(app.windows["Crop"].exists)
}
```

Use explicit start and end coordinates rather than relying on the element
center. Add the `imageCanvas` accessibility identifier in production.

- [ ] **Step 8: Run focused core tests and build**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/imageview-swiftpm-cache \
swift test --scratch-path /private/tmp/imageview-task2-green \
  --filter 'CropGeometry|CropSave'
swift build
```

Expected: focused tests and compilation pass.

- [ ] **Step 9: Commit Task 2**

```bash
git add Sources/ImageviewCore/CropGeometry.swift \
  Sources/ImageviewApp/ImageCanvasView.swift \
  Sources/ImageviewApp/ViewerWindowController.swift \
  Sources/ImageviewApp/AppDelegate.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/CropGeometryTests.swift \
  Tests/ImageviewAppUITests/ImageviewAppUITests.swift
git add -u Sources/ImageviewApp/CropPanelController.swift
git commit -m "feat: crop and overwrite directly on canvas"
```

---

### Task 3: Shared Delete command, reduced toolbar, and Picview-structured menu

**Files:**
- Modify: `Sources/ImageviewApp/ViewerSession.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Modify: `Sources/ImageviewApp/InspectorViewController.swift`
- Modify: `Sources/ImageviewApp/GridViewController.swift`
- Modify: `Sources/ImageviewApp/ImageCanvasView.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`

**Interfaces:**
- Produces: `ViewerSession.moveCurrentToTrash() throws`
- Produces: `ViewerWindowController.deleteCurrent(_:)`
- Produces: `ViewerWindowController.copyCurrentImage(_:)`
- Produces: `ViewerWindowController.setSortOrder(_:)`
- Consumes: Task 1 `MediaIndex.removeCurrent()` and `.delete` shortcut.
- Consumes: existing rotate, flip, fit, actual-size, OCR, Pin, Finder and Finder-label behaviors.

- [ ] **Step 1: Add failing toolbar and deletion UI assertions**

Add:

```swift
func testToolbarUsesDeleteAndOmitsRemovedButtons() {
    XCTAssertTrue(app.toolbars.buttons["Delete"].exists)
    XCTAssertFalse(app.toolbars.buttons["Pin Image"].exists)
    XCTAssertFalse(app.toolbars.buttons["Pin Clipboard"].exists)
    XCTAssertFalse(app.toolbars.buttons["Extract Subject"].exists)
}

func testDeleteKeyMovesCurrentFixtureToTrashAndSelectsNext() {
    app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
    XCTAssertTrue(app.windows["green.png · 1 / 3"].waitForExistence(timeout: 5))
}
```

The fixture directory is temporary, so moving `blue.png` to Trash cannot affect
user files.

- [ ] **Step 2: Add a failing right-click menu UI assertion**

Right-click `app.otherElements["imageCanvas"]` and assert these real menu items:
`Recognize Text`, `Actual Size`, `Fit to Window`, `Sort`, `Image Processing`,
`Finder Label`, `Pin to Desktop`, `Show in Finder`, `Open Default`, `Copy`, and
`Delete`.

- [ ] **Step 3: Build the shared trash mutation**

Implement:

```swift
func moveCurrentToTrash() throws {
    guard let current = index.current else {
        throw ImageDecodeError.cannotOpen
    }
    _ = try FileManager.default.trashItem(at: current.url, resultingItemURL: nil)
    _ = index.removeCurrent()
    decodeCurrent()
}
```

The file operation happens before the index mutation, so failure leaves the
session unchanged.

- [ ] **Step 4: Route every Delete entry to the shared action**

- Add `ToolbarID.delete`, symbol `trash`, label `toolbar.delete`, and action
  `deleteCurrent(_:)`.
- Remove Pin, Pin Clipboard, and Subject from toolbar allowed/default IDs and
  toolbar item construction.
- `deleteCurrent(_:)` calls `session.moveCurrentToTrash()` and presents
  `error.delete_failed` on failure.
- Add an Edit-menu Delete item using `.delete`.
- Change `InspectorViewController` so its Trash button invokes
  `onDeleteRequested`; it must no longer call `FileManager` itself.

- [ ] **Step 5: Build the context menu from supported actions**

Assign a menu to `ImageCanvasView` with this order:

1. Recognize Text
2. Actual Size, Fit to Window
3. Sort submenu with all seven `MediaSortOrder` values
4. Image Processing submenu with rotate left/right, flip horizontal/vertical,
   and Crop
5. Finder Label submenu with tags `0...7`
6. Pin to Desktop, Show in Finder, Open Default
7. Copy, Delete

Set action targets to `ViewerWindowController`. Track the selected sort order in
the controller, expose a small `GridViewController.selectSortOrder(_:)` method
so grid and menu remain synchronized, and apply a checkmark to the current sort
and Finder label. Use `NSMenuItemValidation` to disable current-image commands
when `session.snapshot.current` is `nil`.

- [ ] **Step 6: Add the direct file and clipboard actions**

Use `window?.representedURL`/`session.snapshot.current?.url` for Finder and
default-app actions. Copy the rendered `CGImage` to `NSPasteboard.general`.
Set Finder labels with `URLResourceValues.labelNumber`, then refresh the current
folder so the inspector and menu checkmark update.

- [ ] **Step 7: Add English and Simplified Chinese text**

Add exact keys for `toolbar.delete`, `menu.crop_and_save`, `menu.sort`,
`menu.image_processing`, `menu.finder_label`, `menu.pin_desktop`,
`menu.delete`, and `error.delete_failed`. Reuse existing strings for OCR, zoom,
rotation, flip, Finder, labels, Copy, and Open Default.

- [ ] **Step 8: Run the full Swift test suite and compile**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/imageview-swiftpm-cache \
swift test --scratch-path /private/tmp/imageview-task3-green
swift build
```

Expected: all Swift tests pass and Imageview compiles.

- [ ] **Step 9: Commit Task 3**

```bash
git add Sources/ImageviewApp/ViewerSession.swift \
  Sources/ImageviewApp/ViewerWindowController.swift \
  Sources/ImageviewApp/AppDelegate.swift \
  Sources/ImageviewApp/InspectorViewController.swift \
  Sources/ImageviewApp/GridViewController.swift \
  Sources/ImageviewApp/ImageCanvasView.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewAppUITests/ImageviewAppUITests.swift
git commit -m "feat: add viewer context and delete commands"
```

---

### Task 4: Package the supplied app icon

**Files:**
- Add: `Imageview.icns`
- Modify: `Info.plist`
- Modify: `scripts/build-app.sh`
- Modify: `scripts/smoke-test.sh`
- Modify: `README.md`

**Interfaces:**
- Produces: `dist/Imageview.app/Contents/Resources/Imageview.icns`
- Produces: `CFBundleIconFile = Imageview.icns`
- Consumes: the user-supplied root `Imageview.icns`.

- [ ] **Step 1: Make the smoke test require the icon**

Add:

```bash
test -f "$app_path/Contents/Resources/Imageview.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' \
  "$app_path/Contents/Info.plist")" = "Imageview.icns"
```

- [ ] **Step 2: Run the smoke test and verify RED**

Run:

```bash
./scripts/smoke-test.sh
```

Expected: failure because the current app bundle has no packaged
`Resources/Imageview.icns` and no `CFBundleIconFile`.

- [ ] **Step 3: Add the bundle declaration and copy**

Add to `Info.plist`:

```xml
<key>CFBundleIconFile</key>
<string>Imageview.icns</string>
```

Add to `scripts/build-app.sh` after the localization resources:

```bash
cp "$repo_root/Imageview.icns" "$resources_path/Imageview.icns"
```

- [ ] **Step 4: Update the README**

Replace the crop-panel instructions with direct on-canvas selection, `⌘K`
overwrite, Delete/Trash behavior, and the supported right-click menu. Remove
toolbar wording that says Pin and Extract Subject are present.

- [ ] **Step 5: Build and verify the icon**

Run:

```bash
./scripts/build-app.sh
./scripts/smoke-test.sh
```

Expected: universal build succeeds and the smoke test passes the icon,
architecture, signing, resources, and one-second launch checks.

- [ ] **Step 6: Commit Task 4**

```bash
git add Imageview.icns Info.plist scripts/build-app.sh scripts/smoke-test.sh README.md
git commit -m "feat: package the Imageview app icon"
```

---

### Task 5: End-to-end verification and local test handoff

**Files:**
- Verify: all modified source, test, localization, script, and documentation files
- Deliver: `dist/Imageview.app`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: a clean local `main` commit and a verified universal test app.

- [ ] **Step 1: Run the complete unit test suite**

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/imageview-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/imageview-swiftpm-cache \
swift test --scratch-path /private/tmp/imageview-final
```

Expected: every Swift Testing test passes with zero failures.

- [ ] **Step 2: Run UI tests**

```bash
./scripts/run-ui-tests.sh
```

Expected: navigation, grid, direct crop, toolbar visibility, context menu,
language, corrupt-file recovery, and temporary-fixture Delete tests pass. If
macOS security blocks the runner, stop and request the user's authorization
before retrying; do not describe a blocked runner as an application failure.

- [ ] **Step 3: Review the exact diff**

Run:

```bash
git status --short
git diff --check
git log --oneline -8
```

Confirm there are no unrelated files, generated build products, temporary
fixtures, credentials, or changes outside the approved scope.

- [ ] **Step 4: Request a read-only subagent review**

Ask the reviewer to check Delete failure ordering, multiple-file deletion,
`⌘K` unsupported formats, crop cancel/commit state, context-menu target wiring,
toolbar omissions, bilingual text, and icon packaging. Apply only confirmed
findings, with a failing regression test before each behavior fix.

- [ ] **Step 5: Rebuild the exact reviewed state**

```bash
./scripts/build-app.sh
./scripts/smoke-test.sh
```

Expected: `dist/Imageview.app` is universal, ad-hoc signed, launches, contains
both localizations, and uses `Imageview.icns`.

- [ ] **Step 6: Hand off the local app**

Report the final local commit, exact unit/UI/smoke results, any macOS
environment limitation, and provide the clickable app path:

```text
/Users/cary/py/picview/dist/Imageview.app
```
