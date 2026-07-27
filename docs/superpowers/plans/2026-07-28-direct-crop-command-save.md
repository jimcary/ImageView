# Direct Crop and Command-S Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make plain primary-button dragging create a crop selection immediately, retain Option-drag panning, and save the crop safely with Command-S.

**Architecture:** Add a Foundation/Core Graphics interaction policy that maps drag context to crop, pan, or no action. `ImageCanvasView` uses that policy and synchronously asks `ViewerWindowController` to create the existing validated crop transaction before starting a selection; Command-S routes to the existing atomic overwrite action.

**Tech Stack:** Swift 6.1, AppKit, Core Graphics, Swift Testing, XCTest UI tests, Swift Package Manager.

## Global Constraints

- Support macOS 12 and newer.
- Preserve existing Command-K behavior.
- Command-S must never overwrite without a valid crop transaction and selection.
- Option-primary-drag is the only primary-button panning gesture.
- Add no external dependencies.
- Keep local `main`; do not push a remote.

---

### Task 1: Drag Intent and Command-S Contracts

**Files:**
- Create: `Sources/ImageviewCore/ImageCanvasInteraction.swift`
- Create: `Tests/ImageviewCoreTests/ImageCanvasInteractionTests.swift`
- Modify: `Sources/ImageviewCore/AppPreferences.swift`
- Modify: `Tests/ImageviewCoreTests/AppPreferencesTests.swift`
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`

**Interfaces:**
- Produces: `ImageCanvasInteraction.primaryDragIntent(startsInsideImage:optionPressed:) -> ImageCanvasDragIntent?`.
- Produces: `ShortcutCommand.save` with Command-S.
- Consumes: `AppDelegate.commitCropAndOverwrite(_:)`.

- [ ] **Step 1: Write failing interaction tests**

```swift
@Test
func plainImageDragStartsCropAndOptionDragPans() {
    #expect(
        ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: true,
            optionPressed: false
        ) == .cropSelection
    )
    #expect(
        ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: true,
            optionPressed: true
        ) == .pan
    )
    #expect(
        ImageCanvasInteraction.primaryDragIntent(
            startsInsideImage: false,
            optionPressed: false
        ) == nil
    )
}
```

Extend the shortcut test:

```swift
#expect(
    AppPreferences.defaultShortcut(for: .save)
        == Shortcut(command: .save, key: "s", modifiers: [.command])
)
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --disable-sandbox --filter plainImageDragStartsCropAndOptionDragPans
swift test --disable-sandbox --filter requestedCommandsUseTheDocumentedDefaultShortcuts
```

Expected: compilation fails because the interaction policy and `.save` do not
exist.

- [ ] **Step 3: Implement the policy and shortcut**

```swift
public enum ImageCanvasDragIntent: Equatable, Sendable {
    case cropSelection
    case pan
}

public enum ImageCanvasInteraction {
    public static func primaryDragIntent(
        startsInsideImage: Bool,
        optionPressed: Bool
    ) -> ImageCanvasDragIntent? {
        guard startsInsideImage else { return nil }
        return optionPressed ? .pan : .cropSelection
    }
}
```

Add `.save` to `ShortcutCommand` and return:

```swift
Shortcut(command: command, key: "s", modifiers: [.command])
```

Add a File > Save menu item that targets
`commitCropAndOverwrite(_:)` using `.save`. The existing validation for this
selector keeps Command-S disabled until `canCommitCrop` is true. Add
`shortcut.save` labels in English and Simplified Chinese.

- [ ] **Step 4: Run focused and full Swift tests**

```bash
swift test --disable-sandbox --filter plainImageDragStartsCropAndOptionDragPans
swift test --disable-sandbox --filter requestedCommandsUseTheDocumentedDefaultShortcuts
swift test --disable-sandbox
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/ImageviewCore/ImageCanvasInteraction.swift \
  Sources/ImageviewCore/AppPreferences.swift \
  Sources/ImageviewApp/AppDelegate.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/ImageCanvasInteractionTests.swift \
  Tests/ImageviewCoreTests/AppPreferencesTests.swift
git commit -m "feat: add direct crop interaction contracts"
```

### Task 2: Automatic Crop Transaction and Canvas Selection

**Files:**
- Modify: `Sources/ImageviewApp/ImageCanvasView.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`

**Interfaces:**
- Consumes: `ImageCanvasInteraction.primaryDragIntent(startsInsideImage:optionPressed:)`.
- Produces: `ImageCanvasView.onBeginCropRequested: (() -> Bool)?`.
- Consumes: `ViewerWindowController.beginCrop(_:)`.

- [ ] **Step 1: Change the UI regression contract**

Rename `testCropSelectionAndCommandKOverwriteOriginal` to
`testDirectCropSelectionAndCommandSOverwriteOriginal`. Remove:

```swift
app.toolbars.buttons["Crop"].click()
```

and replace the commit action with:

```swift
app.typeKey("s", modifierFlags: .command)
```

The test must still verify that the original JPEG path contains a decodable
image with smaller width and height.

- [ ] **Step 2: Implement automatic crop entry**

Add to `ImageCanvasView`:

```swift
var onBeginCropRequested: (() -> Bool)?
```

In `mouseDown(with:)`, calculate the displayed image rectangle and drag intent.
For `.pan`, set `lastDragPoint`. For `.cropSelection`, call
`onBeginCropRequested` when not already in crop mode, require it to return
`true`, then reuse the existing crop handle/new-selection setup. A drag outside
the image does nothing.

In `ViewerWindowController.configureCallbacks()`:

```swift
canvas.onBeginCropRequested = { [weak self] in
    guard let self else { return false }
    self.beginCrop(nil)
    return self.canvas.isCropMode
}
```

This preserves all media identity, decode generation, page-count, Escape, and
atomic replacement checks already owned by `beginCrop(_:)` and
`commitCropAndOverwrite(_:)`.

- [ ] **Step 3: Compile tests and package the App**

Run:

```bash
swift test --disable-sandbox
xcodebuild build-for-testing -project Imageview.xcodeproj \
  -scheme ImageviewAppUITests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/imageview-direct-crop-ui
./scripts/build-app.sh
```

Expected: all Swift tests pass, the UI test target compiles, and
`dist/Imageview.app` is rebuilt.

- [ ] **Step 4: Verify the packaged artifact**

```bash
codesign --verify --deep --strict --verbose=2 dist/Imageview.app
lipo -info dist/Imageview.app/Contents/MacOS/Imageview
git diff --check
```

Expected: signature is valid, both `x86_64` and `arm64` are present, and the diff
has no whitespace errors.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/ImageviewApp/ImageCanvasView.swift \
  Sources/ImageviewApp/ViewerWindowController.swift \
  Tests/ImageviewAppUITests/ImageviewAppUITests.swift
git commit -m "feat: start crop selection from primary drag"
```
