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
- Open Grid to browse thumbnails, then select an image to return to the viewer.
- Choose Crop, adjust the crop, then choose Save As to export JPEG, PNG, TIFF, or HEIC. Overwrite is available only for those source formats and first validates a temporary file.
- Use Settings to select English, Simplified Chinese, or follow the system language.

## Privacy and licensing

Imageview works entirely on your Mac. It has no online licensing, account sign-in, telemetry, or network service requirement. Images, edits, pins, and recognized text remain local unless you explicitly save, copy, or share them.
