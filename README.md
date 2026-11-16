<p align="center">
  <img src="assets/ImageView-app-icon.png" alt="ImageView 应用图标" width="128">
</p>

<h1 align="center">ImageView</h1>

Imageview is a local macOS image viewer for macOS 12 and later. It is a universal app: the packaged release includes both Apple Silicon and Intel executables.

## 主要功能与亮点

- **便捷浏览**：打开单张图片、多张图片或文件夹，通过方向键、工具栏、缩略图栏和网格浏览；支持全屏、缩放、适应窗口和实际尺寸查看。
- **整理与查找**：在网格中按格式和 Finder 标签筛选，按名称、扩展名、日期、Finder 顺序等排序；支持显示文件信息、在 Finder 中定位和移到废纸篓。
- **图片处理**：支持旋转、水平或垂直翻转、画布裁剪，以及通过右键菜单调整像素尺寸；调整大小提供常用尺寸预设、自定义宽高和等比缩放。
- **格式转换**：右键选择「格式转换」，可将当前显示的图片保存为 JPG、PNG、GIF 或 WebP 新文件，不会覆盖已有文件。
- **动态图片与文档**：播放 GIF、APNG、WebP 和 HEICS 动画，浏览 PDF 等多页文档，并可按设置的间隔播放幻灯片。
- **文字识别与贴图**：在本机识别图片文字，结果可在信息侧栏中选择和复制；可将图片或剪贴板图片贴到桌面。
- **符合使用习惯**：支持中文、英文及跟随系统语言，可设置快捷键、缩略图大小、循环浏览、文件夹递归扫描和缓存上限。
- **本地运行、原生体验**：无需账号或网络服务，支持 macOS 12 及以上版本，并提供 Intel 与 Apple 芯片通用构建。

常见支持格式包括 JPEG、PNG、GIF、TIFF、BMP、HEIC/HEIF、PDF、WebP、AVIF、PSD、ICO、ICNS 及部分 RAW；实际解码能力可能因 macOS 版本和图片格式而异。

调整大小适用于单帧图片，单边不超过 16,384 像素、总像素不超过 1 亿。尺寸调整后先显示编辑结果；按 **⌘S** 会覆盖支持格式的原文件，裁剪完成后按 **⌘K** 也会覆盖原文件。保存前请自行备份需要保留的原图。

格式转换导出当前显示的帧或页，不保留动画或多页内容；WebP 导出不保留原图元数据，尺寸限制为单边 16,383 像素、总计 1 亿像素。

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
- Choose Crop, then drag directly on the canvas to create, move, or resize the selection. Press ⌘K to overwrite a supported original image.
- Right-click and choose Resize to set pixel dimensions for a single-frame image. Press ⌘S to overwrite a supported original image with the current edits.
- Right-click and choose Convert Format to export the displayed frame or page as a new JPG, PNG, GIF, or WebP file. Existing files are not overwritten. WebP export does not preserve source metadata and is limited to 16,383 pixels per side and 100 million pixels total.
- Press Delete to move the current image to the Trash.
- Right-click the canvas for OCR, actual size, fit to window, resizing, sorting, rotate/flip/crop, Finder labels, pinning, Finder/default-app actions, copy, and Delete.
- OCR runs locally.
- Settings includes English, Simplified Chinese, system language, single/multi-window behavior, folder recursion, thumbnail sizing, slideshow interval, cache size, and configurable shortcuts.
- User-selected folders are remembered with security-scoped bookmarks. Imageview never requests Full Disk Access.

## Privacy and licensing

Imageview works entirely on your Mac. It has no online licensing, account sign-in, telemetry, or network service requirement. Images, edits, pins, and recognized text remain local unless you explicitly save, copy, or share them.

WebP encoding uses [libwebp](https://github.com/webmproject/libwebp) via [libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode). Its license and patent notice are included in the app bundle.
