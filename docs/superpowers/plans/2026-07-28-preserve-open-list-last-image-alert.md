# Preserve Open List and Last Image Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Finder search-result file lists after in-place saves and alert
after manual forward navigation enters the final image.

**Architecture:** Refresh only the overwritten item and invalidate its decoded
cache rather than reopening it through the single-file folder-scan path. Return
a navigation outcome from `MediaIndex`, and let the viewer controller display a
localized alert only for manual forward navigation.

**Tech Stack:** Swift 6, AppKit, Swift Testing, XCTest UI tests

## Global Constraints

- Keep the exact ordered file list supplied by Finder search results.
- Preserve the current list position after rotation or crop overwrite.
- Keep atomic overwrite validation and replacement unchanged.
- Alert only when manual forward navigation enters the final item.
- Do not alert for initial open, backward wrap, slideshow, one-item, or empty lists.
- Keep the existing loop-navigation preference unchanged.
- Add no dependencies and do not launch UI tests; the user will test manually.
- Work on the existing local `main` branch and do not push.

---

### Task 1: Preserve the Explicit List After Overwrite

**Files:**
- Modify: `Sources/ImageviewCore/MediaIndex.swift`
- Modify: `Sources/ImageviewApp/ViewerSession.swift`
- Test: `Tests/ImageviewCoreTests/MediaIndexTests.swift`

**Interfaces:**
- Consumes: `MediaIndex.currentIndex`, `MediaItem`, `CostCache.removeValue(for:)`,
  `FolderScanner.scan(urls:)`, and `ViewerSession.decodeCurrent()`.
- Produces: `MediaIndex.replaceCurrent(with:) -> MediaItem?`.

- [ ] **Step 1: Write the failing list-preservation test**

```swift
@Test
func replacingCurrentItemPreservesExplicitListAndPosition() {
    let original = mediaFixtures(["search-a.jpg", "search-b.jpg", "search-c.jpg"])
    var index = MediaIndex(items: original)
    index.select(id: original[1].id)
    let refreshed = MediaItem(
        url: original[1].url,
        resourceIdentifier: "replacement-id",
        fileSize: 999
    )

    let replaced = index.replaceCurrent(with: refreshed)

    #expect(replaced?.id == original[1].id)
    #expect(index.items.map(\.url.lastPathComponent) == [
        "search-a.jpg", "search-b.jpg", "search-c.jpg",
    ])
    #expect(index.currentIndex == 1)
    #expect(index.current?.id == "replacement-id")
}
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --disable-sandbox \
  --filter replacingCurrentItemPreservesExplicitListAndPosition
```

Expected: compilation fails because `MediaIndex.replaceCurrent(with:)` does not
exist.

- [ ] **Step 3: Implement current-item replacement**

```swift
@discardableResult
public mutating func replaceCurrent(with replacement: MediaItem) -> MediaItem? {
    guard let currentIndex, items.indices.contains(currentIndex) else {
        return nil
    }
    let previous = items[currentIndex]
    items[currentIndex] = replacement
    return previous
}
```

- [ ] **Step 4: Refresh in place after a successful overwrite**

In `ViewerSession.overwriteCurrent(...)`, replace
`open(urls: [current.url])` with:

```swift
let cacheKey = MediaSubimageKey(mediaID: current.id, index: 0)
cache.removeValue(for: cacheKey)
if protectedCacheKey == cacheKey {
    protectedCacheKey = nil
}
let refreshed = FolderScanner().scan(urls: [current.url]).first ?? current
_ = index.replaceCurrent(with: refreshed)
decodeCurrent()
```

This keeps every other explicit item and the selected array position intact.

- [ ] **Step 5: Run the focused and full Core tests**

```bash
swift test --disable-sandbox \
  --filter replacingCurrentItemPreservesExplicitListAndPosition
swift test --disable-sandbox
```

Expected: the focused test and full suite pass.

- [ ] **Step 6: Commit the list fix**

```bash
git add Sources/ImageviewCore/MediaIndex.swift \
  Sources/ImageviewApp/ViewerSession.swift \
  Tests/ImageviewCoreTests/MediaIndexTests.swift
git commit -m "fix: preserve explicit list after overwrite"
```

### Task 2: Alert When Manual Navigation Enters the Final Image

**Files:**
- Modify: `Sources/ImageviewCore/MediaIndex.swift`
- Modify: `Sources/ImageviewApp/ViewerSession.swift`
- Modify: `Sources/ImageviewApp/ViewerWindowController.swift`
- Modify: `Sources/ImageviewApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Tests/ImageviewCoreTests/MediaIndexTests.swift`
- Modify: `Tests/ImageviewAppUITests/ImageviewAppUITests.swift`

**Interfaces:**
- Consumes: `NavigationDirection`, `MediaIndex.move(_:wraps:)`,
  `ViewerSession.move(_:)`, and `ViewerWindowController.presentMessage`.
- Produces: `NavigationResult` with `item: MediaItem` and
  `enteredFinalItem: Bool`.

- [ ] **Step 1: Write failing navigation-outcome tests**

```swift
@Test
func forwardNavigationReportsOnlyWhenItEntersTheFinalItem() {
    let items = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: items)

    #expect(index.move(.next)?.enteredFinalItem == false)
    #expect(index.move(.next)?.enteredFinalItem == true)
    #expect(index.move(.next)?.enteredFinalItem == false)
    #expect(index.currentIndex == 0)
}

@Test
func finalItemReportExcludesBackwardSingleAndEmptyNavigation() {
    let items = mediaFixtures(["a.jpg", "b.jpg"])
    var index = MediaIndex(items: items)
    #expect(index.move(.previous)?.enteredFinalItem == false)

    var single = MediaIndex(items: [items[0]])
    #expect(single.move(.next)?.enteredFinalItem == false)

    var empty = MediaIndex(items: [])
    #expect(empty.move(.next) == nil)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
swift test --disable-sandbox --filter forwardNavigationReportsOnly
swift test --disable-sandbox --filter finalItemReportExcludes
```

Expected: compilation fails because the current move result is `MediaItem`,
which has no `enteredFinalItem`.

- [ ] **Step 3: Return a navigation outcome**

Add:

```swift
public struct NavigationResult: Sendable {
    public let item: MediaItem
    public let enteredFinalItem: Bool
}
```

In `MediaIndex.move`, capture the previous index and return:

```swift
let movesForward: Bool
if case .next = direction {
    movesForward = true
} else {
    movesForward = false
}
let enteredFinalItem = movesForward
    && items.count > 1
    && previousIndex != items.indices.last
    && currentIndex == items.indices.last
return current.map {
    NavigationResult(item: $0, enteredFinalItem: enteredFinalItem)
}
```

Make `ViewerSession.move(_:)` return this result after starting the current-item
decode.

- [ ] **Step 4: Route manual navigation through one controller method**

Add `navigate(_:)` to `ViewerWindowController`. It calls `session.move`, stores
the final item ID when `enteredFinalItem` is true, and displays the alert after
that final item's image becomes available. Route toolbar/menu Previous, Next,
keyboard arrows, and canvas horizontal navigation through this method.
Slideshow continues to call `session.move(.next)` directly.

Use these localization keys:

```text
navigation.last_title = Last Image / 最后一张图片
navigation.last_message = You have reached the end of the opened file list. /
                          已到达打开文件列表的最后一张图片。
```

- [ ] **Step 5: Add compile-time UI coverage**

Add a UI test that opens three explicit fixtures, moves Next twice, and expects
the localized “Last Image” alert after the final image window title appears.
Do not execute the UI test; compile its target only.

- [ ] **Step 6: Verify, rebuild, and commit**

```bash
swift test --disable-sandbox
xcodebuild build-for-testing -quiet -project Imageview.xcodeproj \
  -scheme ImageviewAppUITests -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/imageview-list-alert-ui
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/Imageview.app
lipo -info dist/Imageview.app/Contents/MacOS/Imageview
git diff --check
```

Expected: all Core tests pass, the UI-test target compiles, the app rebuilds,
signature verification succeeds, and `x86_64` plus `arm64` are present.

```bash
git add Sources/ImageviewCore/MediaIndex.swift \
  Sources/ImageviewApp/ViewerSession.swift \
  Sources/ImageviewApp/ViewerWindowController.swift \
  Sources/ImageviewApp/Resources/en.lproj/Localizable.strings \
  Sources/ImageviewApp/Resources/zh-Hans.lproj/Localizable.strings \
  Tests/ImageviewCoreTests/MediaIndexTests.swift \
  Tests/ImageviewAppUITests/ImageviewAppUITests.swift
git commit -m "feat: alert when navigation reaches final image"
```
