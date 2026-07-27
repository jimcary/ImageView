# Rotate Shortcuts and Open With Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Command-L/Command-R rotation shortcuts and a dynamic macOS “Open With” image context submenu.

**Architecture:** Extend the existing preference-backed shortcut commands and route them through the current viewer rotation actions. Query compatible applications with `NSWorkspace`, normalize/sort the results through a small Foundation-only Core helper, and rebuild the submenu whenever it opens.

**Tech Stack:** Swift 6.1, AppKit, Foundation, Swift Testing, XCTest UI tests, Swift Package Manager.

## Global Constraints

- Support macOS 12 and newer.
- Keep English and Simplified Chinese localization only.
- Do not hard-code application names.
- Add no external dependencies.
- Keep local `main`; do not push a remote.

---

### Task 1: Rotation Shortcuts

**Files:**
- Modify: `Sources/ImageviewCore/AppPreferences.swift`
- Modify: `Sources/ImageviewApp/AppDelegate.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ImageviewCoreTests/AppPreferencesTests.swift`

**Interfaces:**
- Consumes: `ViewerWindowController.rotateLeft(_:)` and `rotateRight(_:)`.
- Produces: `ShortcutCommand.rotateLeft`, `ShortcutCommand.rotateRight`, with Command-L and Command-R defaults.

- [ ] **Step 1: Write the failing shortcut test**

Extend the default-shortcut test:

```swift
#expect(
    AppPreferences.defaultShortcut(for: .rotateLeft)
        == Shortcut(command: .rotateLeft, key: "l", modifiers: [.command])
)
#expect(
    AppPreferences.defaultShortcut(for: .rotateRight)
        == Shortcut(command: .rotateRight, key: "r", modifiers: [.command])
)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --disable-sandbox --filter cropAndDeleteUseTheRequestedDefaultShortcuts
```

Expected: compilation fails because `ShortcutCommand` has no rotation cases.

- [ ] **Step 3: Implement the shortcut commands**

Add the cases and defaults:

```swift
case rotateLeft
case rotateRight
```

```swift
case .rotateLeft:
    Shortcut(command: command, key: "l", modifiers: [.command])
case .rotateRight:
    Shortcut(command: command, key: "r", modifiers: [.command])
```

In `AppDelegate`, add key-viewer-only actions and two View menu items:

```swift
@objc private func rotateLeft(_ sender: Any?) {
    keyWindowController?.rotateLeft(sender)
}

@objc private func rotateRight(_ sender: Any?) {
    keyWindowController?.rotateRight(sender)
}
```

Use the existing `NSMenu.addItem(withTitle:action:shortcut:)` helper, and validate
both actions only when `keyWindowController?.hasCurrentItem == true`.

Add `shortcut.rotateLeft` and `shortcut.rotateRight` labels in English and
Simplified Chinese.

- [ ] **Step 4: Run the focused and full Swift test suites**

Run:

```bash
swift test --disable-sandbox --filter cropAndDeleteUseTheRequestedDefaultShortcuts
swift test --disable-sandbox
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/ImageviewCore/AppPreferences.swift \
  Sources/ImageviewApp/AppDelegate.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/AppPreferencesTests.swift
git commit -m "feat: add rotation shortcuts"
```

### Task 2: Dynamic Open With Submenu

**Files:**
- Create: `Sources/ImageviewCore/OpenWithApplications.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `Tests/ImageviewCoreTests/OpenWithApplicationsTests.swift`
- Modify: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`

**Interfaces:**
- Consumes: the current image URL and `NSWorkspace.urlsForApplications(toOpen:)`.
- Produces: `OpenWithApplication(url:displayName:)` rows and the `openCurrentWithApplication(_:)` context-menu action.

- [ ] **Step 1: Write the failing catalog test**

Create a test with duplicate and unsorted application URLs:

```swift
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
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --disable-sandbox --filter openWithApplicationsAreDeduplicatedExcludedAndSorted
```

Expected: compilation fails because `OpenWithApplications` does not exist.

- [ ] **Step 3: Implement the Foundation-only catalog**

Add:

```swift
public struct OpenWithApplication: Equatable, Sendable {
    public let url: URL
    public let displayName: String
}

public enum OpenWithApplications {
    public static func rows(
        from urls: [URL],
        excluding excludedURL: URL?,
        displayName: (URL) -> String
    ) -> [OpenWithApplication]
}
```

Standardize URLs, exclude the current app, deduplicate by standardized URL, and
sort using `localizedStandardCompare`.

- [ ] **Step 4: Add the dynamic AppKit submenu**

Make `ViewerWindowController` conform to `NSMenuDelegate`, retain an
`openWithMenu`, and place an “Open With” submenu immediately after “Open
Default”. In `menuNeedsUpdate(_:)`:

```swift
let urls = NSWorkspace.shared.urlsForApplications(toOpen: imageURL)
let rows = OpenWithApplications.rows(
    from: urls,
    excluding: Bundle.main.bundleURL
) { FileManager.default.displayName(atPath: $0.path) }
```

For each row, create a menu item with a 16×16 application icon, store the app URL
in `representedObject`, and target:

```swift
@objc private func openCurrentWithApplication(_ sender: NSMenuItem) {
    guard let imageURL = session.snapshot.current?.url,
          let applicationURL = sender.representedObject as? URL else {
        return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open(
        [imageURL],
        withApplicationAt: applicationURL,
        configuration: configuration
    ) { [weak self] _, error in
        guard let error else { return }
        Task { @MainActor in
            self?.presentError(title: L10n.text("error.open_failed"), error: error)
        }
    }
}
```

When rows are empty, add one disabled `menu.no_compatible_applications` row.
Add English and Simplified Chinese strings for `menu.open_with`,
`menu.no_compatible_applications`, and `error.open_failed`.

- [ ] **Step 5: Update the UI menu contract**

Insert `"Open With"` after `"Open Default"` in the expected English context-menu
order and assert that its submenu contains at least one enabled application row
for the JPEG fixture.

- [ ] **Step 6: Run tests and package the app**

Run:

```bash
swift test --disable-sandbox
./scripts/build-app.sh
./scripts/smoke-test.sh
```

Expected: all Swift tests pass; the universal app and smoke test pass.

- [ ] **Step 7: Commit Task 2**

```bash
git add Sources/ImageviewCore/OpenWithApplications.swift \
  Sources/ImageviewApp/ViewerWindowController.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/OpenWithApplicationsTests.swift \
  Tests/ImageviewAppUITests/ImageviewAppUITests.swift
git commit -m "feat: add dynamic open-with menu"
```
