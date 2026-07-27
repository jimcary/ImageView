# Imageview Shortcut Action Separation Design

## Goal

Separate save, crop-save, delete, and Finder reveal so each shortcut performs
one predictable action.

## Interaction

- Delete moves the current file to the Trash and selects the next available
  image.
- Command-K commits a valid crop selection and atomically overwrites the
  original image.
- Command-S atomically saves rotation and flip edits to the original image.
- Command-S does not commit an active crop selection. While crop selection is
  active, the save action is unavailable and the selection remains unchanged.
- Command-Return reveals the current file in Finder.

## Architecture

Add a distinct save action in `ViewerWindowController` instead of routing
Command-S through `commitCropAndOverwrite(_:)`. The save action creates the same
media/decode identity guard used by crop overwrite, but only when crop mode is
inactive. It reuses the existing validated atomic overwrite pipeline.

Add `ShortcutCommand.showInFinder` with Command-Return as its default and route
the File menu action to the existing `showCurrentInFinder(_:)` method. Keep
Delete and Command-K on their existing tested actions.

## Safety

- Save is disabled without a decoded current image, for multi-image sources,
  or while a crop transaction is active.
- Unsupported output formats keep the existing overwrite error.
- All overwrites continue to validate the current media identity, decode
  generation, subimage index, temporary output, and final replacement.
- Finder reveal and Delete require a key viewer window with a current item.

## Verification

- Unit tests cover the Delete, Command-K, Command-S, and Command-Return default
  shortcuts.
- UI tests prove Command-S saves a rotation without cropping, Command-K commits
  a crop selection, Command-Return reveals the current file action, and Delete
  still removes the current fixture.
- Run the full Swift test suite, compile the UI-test target, rebuild the local
  app, and validate its signature and universal architectures.
