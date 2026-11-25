<p align="center">
  <img src="assets/ImageView-app-icon.png" alt="ImageView 应用图标" width="128">
</p>

<h1 align="center">ImageView</h1>

**让 Mac 上的日常看图更顺手。** ImageView 是一款原生 macOS 图片查看器。打开图片或文件夹，就能用键盘和缩略图快速浏览，需要时可直接裁剪、调整大小或转换格式。所有操作都在本机完成。

支持 macOS 12 及以上，提供 Intel 与 Apple 芯片通用版。[下载安装包](https://github.com/jimcary/ImageView/releases/latest)

## 主要功能与亮点

### 打开与浏览

- 通过 Finder、拖放或 **⌘O** 打开单张图片、多张图片或文件夹。打开单张图后，也可以继续浏览同目录里的图片。
- 使用 **← / →**、工具栏或横向滚动切换图片，也可以从底部缩略图栏直接跳到指定图片。
- 用滚轮或触控板捏合缩放，按住 **⌥** 拖动平移。**⌘0** 适应窗口，**⌘1** 查看实际尺寸，**⌃⌘F** 进入全屏。
- 按 **G** 切换网格，按图片格式或 Finder 标签筛选。支持按名称、扩展名、创建日期、修改日期、Finder 顺序和标签排序，也可以随机排列。
- 播放 GIF、APNG、WebP 和 HEICS 动画。浏览 PDF 等多页文档时，可用工具栏逐页切换。幻灯片的播放间隔和循环行为可以设置。

### 查看信息与管理文件

- 按 **I** 打开信息侧栏，查看路径、文件大小、日期和可读取的图片元数据。
- 给图片设置 Finder 彩色标签，在 Finder 中显示（**⌘↩**），或用默认应用及其他兼容应用打开。
- 支持复制图片、复制文件路径、打印（**⌘P**），以及用 **⌫** 将当前图片移到废纸篓。
- 从「最近打开」重新打开文件，可手动清空列表或设为退出时清空。

### 编辑与导出

- 每次以 90° 向左（**⌘L**）或向右（**⌘R**）旋转，也可水平或垂直翻转。
- 直接在画布上拖出裁剪区域，用网格和边缘控制点调整。按 **Esc** 取消本次裁剪，完成后可按 **⌘K** 保存。
- 右键选择「调整大小」，可自定义像素宽高、锁定比例，或套用常用尺寸预设。调整大小适用于单帧图片，单边上限为 16,384 像素，总像素上限为 1 亿。
- 使用 **⌘S** 将当前编辑写入受支持的 JPEG、PNG、TIFF、HEIC 或 HEIF 单帧原文件。**⌘S** 和 **⌘K** 都会覆盖原文件。
- 右键选择「格式转换」，将当前图片、动画帧或文档页直接存为 JPG、PNG、GIF 或 WebP。文件保存到原图目录，重名时按 `照片.jpg`、`照片2.jpg`、`照片3.jpg` 的顺序选择可用名称，无需确认。
- 转换只导出当前显示的帧或页。WebP 导出不保留原图元数据，单边上限为 16,383 像素，总像素上限为 1 亿。

### 文字识别与桌面贴图

- 按 **⌘⇧R** 在本机识别图片中的简体中文和英文，结果显示在信息侧栏，可选择和复制。
- 按 **P** 将当前图片贴到桌面，或按 **⌘⇧V** 将剪贴板中的图片或文字贴到桌面。贴图以浮窗显示，可调透明度并切换缩略图模式。

### 个性化设置

- 支持简体中文、英文和跟随系统语言，查看器适配 macOS 的浅色和深色外观。
- 可设置单窗口或多窗口打开、关闭最后一个窗口后退出，以及打开文件夹时包含子文件夹。
- 可自定义常用快捷键、缩略图栏显示及大小、贴图默认透明度和图片缓存上限。

常见支持格式包括 JPEG、PNG、GIF、TIFF、BMP、HEIC/HEIF、PDF、WebP、AVIF、PSD、ICO、ICNS 及部分 RAW；实际解码能力可能因 macOS 版本和图片格式而异。

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
- Right-click and choose Convert Format to save the displayed frame or page as JPG, PNG, GIF, or WebP in the original folder. Export starts immediately and uses the original base name, adding a number if needed (for example, `photo.jpg`, `photo2.jpg`, `photo3.jpg`). WebP export does not preserve source metadata and is limited to 16,383 pixels per side and 100 million pixels total.
- Press Delete to move the current image to the Trash.
- Right-click the canvas for OCR, actual size, fit to window, resizing, sorting, rotate/flip/crop, Finder labels, pinning, Finder/default-app actions, copy, and Delete.
- OCR runs locally.
- Settings includes English, Simplified Chinese, system language, single/multi-window behavior, folder recursion, thumbnail sizing, slideshow interval, cache size, and configurable shortcuts.
- User-selected folders are remembered with security-scoped bookmarks. Imageview never requests Full Disk Access.

## Privacy

Imageview works entirely on your Mac. It has no online licensing, account sign-in, telemetry, or network service requirement. Images, edits, pins, and recognized text remain local unless you explicitly save, copy, or share them.

## License

ImageView's source code is available under the [MIT License](LICENSE). Third-party dependencies retain their own licenses.

WebP encoding uses [libwebp](https://github.com/webmproject/libwebp) via [libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode). Its license and patent notice are included in the app bundle.
