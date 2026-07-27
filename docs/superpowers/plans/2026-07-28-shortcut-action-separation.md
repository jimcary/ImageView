# Imageview Shortcut Action Separation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Delete, Command-K, Command-S, and Command-Return distinct, tested actions.

**Architecture:** Keep the existing configurable shortcut model and AppKit menu
routing. Add one save action that constructs the existing identity-checked
overwrite transaction only outside crop mode, while Command-K remains the only
crop commit action. Route Command-Return to the existing Finder reveal method.

**Tech Stack:** Swift 6, AppKit, Swift Testing, XCTest UI tests

## Global Constraints

- Keep the current local `main` workflow; do not create a branch or push.
- Add no dependencies and do not refactor unrelated viewer code.
- Delete moves the current file to Trash.
- Command-K commits a valid crop selection.
- Command-S never commits an active crop selection.
- Command-Return reveals the current file in Finder.
- Reuse the existing validated atomic overwrite path.

---

### Task 1: Shortcut Contracts

**Files:**
- Modify: `Sources/ImageviewCore/AppPreferences.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/ImageviewCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Consumes: `ShortcutCommand`, `Shortcut`, and
  `AppPreferences.defaultShortcut(for:)`.
- Produces: `ShortcutCommand.showInFinder` with Command-Return as its default.

- [ ] **Step 1: Write the failing shortcut test**

Extend `requestedCommandsUseTheDocumentedDefaultShortcuts()` with:

```swift
#expect(
    AppPreferences.defaultShortcut(for: .showInFinder)
        == Shortcut(command: .showInFinder, key: "\r", modifiers: [.command])
)
```

The existing expectations for `.delete`, `.crop`, and `.save` remain unchanged.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
swift test --disable-sandbox --filter requestedCommandsUseTheDocumentedDefaultShortcuts
```

Expected: compilation fails because `ShortcutCommand.showInFinder` does not
exist.

- [ ] **Step 3: Add the minimal shortcut contract**

Add `case showInFinder` and this default:

```swift
case .showInFinder:
    Shortcut(command: command, key: "\r", modifiers: [.command])
```

Add `shortcut.showInFinder` as “Show in Finder” and “在 Finder 中显示” to the
two localization files.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run:

```bash
swift test --disable-sandbox --filter requestedCommandsUseTheDocumentedDefaultShortcuts
```

Expected: the focused shortcut test passes.

- [ ] **Step 5: Commit the shortcut contract**

```bash
git add Sources/ImageviewCore/AppPreferences.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/AppPreferencesTests.swift
git commit -m "feat: add Finder reveal shortcut"
```

### Task 2: Separate Save and Crop Actions

**Files:**
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`

**Interfaces:**
- Consumes: `ViewerSession.Snapshot`, `CropTransaction`,
  `ViewerSession.overwriteCurrent(transaction:format:metadataPolicy:)`, and
  `ViewerWindowController.showCurrentInFinder(_:)`.
- Produces: `ViewerWindowController.saveCurrentEdits(_:)` and
  `ViewerWindowController.canSaveCurrentEdits`.

- [ ] **Step 1: Change UI tests to express the required routing**

Rename the crop test to `testDirectCropSelectionAndCommandKOverwriteOriginal`
and change its key press to:

```swift
app.typeKey("k", modifierFlags: .command)
```

Add a rotation save test:

```swift
func testCommandSSavesRotationWithoutCropSelection() {
    let originalURL = fixturesURL.appendingPathComponent("blue.jpg")
    XCTAssertEqual(decodedPixelSize(at: originalURL), CGSize(width: 800, height: 600))

    app.typeKey("r", modifierFlags: .command)
    app.typeKey("s", modifierFlags: .command)

    XCTAssertTrue(waitForDecodedPixelSize(
        at: originalURL,
        equalTo: CGSize(width: 600, height: 800)
    ))
}
```

Keep the existing Delete UI tests as the regression coverage for the Delete
key.

- [ ] **Step 2: Add the test helper and run the new UI test to verify RED**

Add:

```swift
private func waitForDecodedPixelSize(at url: URL, equalTo expected: CGSize) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    repeat {
        if decodedPixelSize(at: url) == expected {
            return true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    return false
}
```

Run:

```bash
xcodebuild test -project Imageview.xcodeproj \
  -scheme ImageviewAppUITests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/imageview-shortcuts-red \
  -only-testing:ImageviewAppUITests/ImageviewAppUITests/testCommandSSavesRotationWithoutCropSelection
```

Expected: the test fails because Command-S points to crop commit and does not
save the rotation.

- [ ] **Step 3: Add the distinct save action**

In `ViewerWindowController`, expose `canSaveCurrentEdits` that requires:

```swift
!canvas.isCropMode
    && snapshot.current != nil
    && snapshot.image != nil
    && snapshot.decodedMediaID == snapshot.current?.id
    && snapshot.decodeGeneration != nil
    && snapshot.decodedSubimageIndex != nil
    && snapshot.subimageCount == 1
```

Add `saveCurrentEdits(_:)`. It guards `canSaveCurrentEdits`, constructs a
`CropTransaction` from the current snapshot identity and recipe, resolves the
source export format, and calls the existing
`session.overwriteCurrent(transaction:format:metadataPolicy:)`. It must not call
`finishCrop()` and must reject execution while crop mode is active.

- [ ] **Step 4: Route menus to the correct actions**

In `AppDelegate`:

```swift
@objc private func saveCurrentEdits(_ sender: Any?) {
    keyWindowController?.saveCurrentEdits(sender)
}

@objc private func showCurrentInFinder(_ sender: Any?) {
    keyWindowController?.showCurrentInFinder(sender)
}
```

Route File > Save / `.save` to `saveCurrentEdits(_:)`. Keep Edit > Crop and
Save / `.crop` routed to `commitCropAndOverwrite(_:)`. Add File > Show in Finder
using `.showInFinder`, and validate save, crop, reveal, and Delete against the
key viewer window.

- [ ] **Step 5: Run focused and full verification**

Run:

```bash
swift test --disable-sandbox
xcodebuild build-for-testing -project Imageview.xcodeproj \
  -scheme ImageviewAppUITests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/imageview-shortcuts-green
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/Imageview.app
lipo -info dist/Imageview.app/Contents/MacOS/Imageview
```

Expected: all Swift tests pass, the UI-test target builds, the app rebuilds,
signature verification succeeds, and both `x86_64` and `arm64` are present.

- [ ] **Step 6: Commit the action separation**

```bash
git add Sources/ImageviewApp/AppDelegate.swift \
  Sources/ImageviewApp/ViewerWindowController.swift \
  Tests/ImageviewAppUITests/ImageviewAppUITests.swift
git commit -m "fix: separate save and crop shortcuts"
```
