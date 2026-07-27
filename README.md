# Imageview

Imageview is a local macOS image viewer for macOS 12 and later. It is a universal app: the packaged release includes both Apple Silicon and Intel executables.

## Build and launch

```bash
./scripts/build-app.sh
open dist/Imageview.app
```

To check a freshly built bundle:

```bash
./scripts/smoke-test.sh
```

Run the Xcode UI tests against that exact local app bundle:

```bash
./scripts/run-ui-tests.sh
```

The script builds `dist/Imageview.app`, passes its absolute path as `IMAGEVIEW_APP_PATH`, and invokes the shared `ImageviewAppUITests` scheme. The UI tests preserve any existing Imageview preferences: each test starts with a clean English baseline and restores the previous preference domain afterward.

Open an image, several images, or a folder from Finder, or pass it directly to the app:

```bash
open -a "$(pwd)/dist/Imageview.app" /path/to/image.png
open -a "$(pwd)/dist/Imageview.app" /path/to/folder
```

## Viewing and editing

- Use the Previous and Next toolbar buttons, or the left and right arrow keys, to navigate a folder.
- Open Grid to browse, filter, and sort thumbnails, then select an image to return to the viewer.
- Animated GIF, APNG, WebP, and HEICS files play locally with cancellable frame decoding.
- PDF and other multi-image documents expose Previous Page and Next Page controls. PDF pages are rendered through Core Graphics for reliable display.
- Slideshow uses the interval configured in Settings and stops at the end when loop navigation is disabled.
- Choose Crop, adjust the crop, then choose Save As to export JPEG, PNG, TIFF, or HEIC. JPEG/HEIC quality and metadata preservation are configurable in the crop panel. Overwrite first validates a sibling temporary file.
- Use Pin Image or Pin Clipboard for floating image/text references. Image pins support original-size and thumbnail modes.
- OCR and subject extraction run locally. Subject extraction appears only on supported macOS versions.
- Settings includes English, Simplified Chinese, system language, single/multi-window behavior, folder recursion, thumbnail sizing, slideshow interval, cache size, and configurable shortcuts.
- User-selected folders are remembered with security-scoped bookmarks. Imageview never requests Full Disk Access.

## Privacy and licensing

Imageview works entirely on your Mac. It has no online licensing, account sign-in, telemetry, or network service requirement. Images, edits, pins, and recognized text remain local unless you explicitly save, copy, or share them.
