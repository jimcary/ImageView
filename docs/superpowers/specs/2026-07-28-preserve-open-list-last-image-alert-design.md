# Imageview Preserve Open List and Last Image Alert Design

## Goal

Keep the exact list of files opened from Finder search results after an
in-place edit, and notify the user when manual forward navigation reaches the
last image.

## Preserve the Opened List

Finder can open multiple search-result files that do not represent every image
in one directory. Imageview must treat that ordered set as the active list.

After rotation or crop overwrite succeeds:

- Keep the existing `MediaIndex.items` and current selection.
- Clear the cached decoded pixels for the overwritten current item.
- Decode that same item again so the viewer shows the saved file.
- Reset the edit recipe through the normal decode path.
- Do not call the single-file open path, because that path intentionally scans
  the file's containing directory.

Folder-backed sessions keep their folder monitor and explicit multi-file
sessions remain explicit multi-file sessions.

## Last Image Alert

When the user manually navigates forward from the penultimate item to the final
item:

- Display the final image normally.
- Then show a warning alert titled “Last Image” / “最后一张图片”.
- The message states that the end of the opened file list has been reached.
- Show the alert for toolbar Next, the Right Arrow shortcut, and horizontal
  swipe navigation.
- Do not show it when the list initially opens on its only item, when navigating
  backward and wrapping to the final item, or during slideshow advancement.
- Existing loop-navigation behavior remains unchanged after the alert is
  dismissed.

## Architecture

`ViewerSession.overwriteCurrent(...)` invalidates the current cache entry and
calls the existing current-item decode path instead of calling
`open(urls: [current.url])`.

`MediaIndex.move(...)` returns a small navigation result containing the selected
item and whether a forward move entered the final position. `ViewerSession`
passes that result back to manual callers. `ViewerWindowController` owns the
localized AppKit alert, so Core and session navigation remain UI-independent.

## Safety

- Atomic overwrite validation and replacement remain unchanged.
- A failed overwrite does not alter the list or selection.
- Re-decoding cannot reuse stale pre-overwrite pixels.
- Empty and one-item lists do not produce the final-image alert.
- Repeated actions at the final item do not claim that the final item was newly
  reached.

## Verification

- A regression test proves an in-place overwrite refresh retains an explicit
  list and selection policy without reopening a containing folder.
- Media-index tests cover entering the final item, wrapping, backward
  navigation, one-item lists, and empty lists.
- UI-test code covers the localized alert after manual forward navigation.
- Run the full Swift test suite, compile the UI-test target without launching
  it, rebuild `dist/Imageview.app`, and verify signing and both architectures.
