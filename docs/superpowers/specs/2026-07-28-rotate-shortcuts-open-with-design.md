# Imageview Rotate Shortcuts and Open With Design

## Goal

Add fixed default shortcuts for rotating the current image and add a Picview-style
“Open With” submenu to the image context menu.

## Behavior

- Command-L rotates the current image left.
- Command-R rotates the current image right.
- Both commands use the existing shortcut preference model, appear in Settings,
  and route through the same rotate actions used by the toolbar and context menu.
- The image context menu adds “Open With” after “Open Default”.
- The submenu is populated from the macOS applications registered to open the
  current image URL. Each row shows the application icon and localized display
  name.
- Selecting an application opens the current image with that exact application.
- Duplicate application URLs are removed and rows are sorted by localized name.
- When no image is selected, or no compatible application is registered, the
  submenu is disabled and displays a disabled empty-state row.

## Implementation

`ShortcutCommand` gains `rotateLeft` and `rotateRight`, with Command-L and
Command-R defaults. `AppDelegate` adds the two commands to the View menu so their
key equivalents are active without opening a context menu.

`ViewerWindowController` owns the dynamic submenu. It refreshes the submenu when
the user opens it, querying `NSWorkspace.urlsForApplications(toOpen:)`. Each menu
item stores its application URL and invokes
`NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`.

No application list is hard-coded and no dependency is added.

## Error Handling

If macOS cannot open the image with the selected application, Imageview presents
its normal localized error alert. Missing current images and empty application
lists remain disabled rather than producing an action.

## Verification

- Unit tests assert the Command-L and Command-R defaults and shortcut conflict
  behavior.
- UI/menu tests assert the new top-level context-menu order and the presence of
  the dynamic submenu.
- The full Swift test suite, universal app build, code-sign validation, and
  smoke test must pass before handoff.
