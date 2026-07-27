# Imageview Direct Crop and Command-S Design

## Goal

Make crop selection the default primary-drag behavior and add Command-S as a
safe crop-and-overwrite shortcut.

## Interaction

- Dragging the primary mouse button from inside the displayed image
  automatically starts a crop transaction and draws a selection.
- Option-primary-drag retains image panning.
- Existing crop handles continue to resize and move an active selection.
- Escape cancels the transaction and restores the complete recipe from before
  the first drag.
- Command-S commits a valid selection through the existing atomic overwrite
  workflow.
- Existing Command-K remains available for compatibility.
- Command-S with no valid selection does not modify the file.

## Architecture

`ImageCanvasView` asks `ViewerWindowController` to begin a crop transaction when
a plain primary drag starts inside the image. The controller reuses
`beginCrop(_:)`, which already verifies decoded media identity, generation,
subimage count, and overwrite eligibility. Once that synchronous request
returns, the canvas starts the same selection drag used by explicit crop mode.

A small Core interaction policy distinguishes crop selection from Option-drag
panning so the decision is covered without AppKit event simulation.

`ShortcutCommand.save` uses Command-S. The App menu routes it to
`commitCropAndOverwrite(_:)`, the same validated action used by Command-K.

## Safety

- A drag outside the image does not create a crop transaction.
- Multi-page and unsupported images keep the existing overwrite rejection.
- Selection creation never bypasses crop media/decode identity checks.
- Failed or absent selections leave the original file untouched.

## Verification

- Unit tests cover plain-drag selection, Option-drag panning, and the Command-S
  default.
- UI tests no longer click the Crop toolbar before drawing a selection and save
  with Command-S.
- The full Swift test suite and UI test target must compile.
- Rebuild and validate the signed universal `dist/Imageview.app`.
