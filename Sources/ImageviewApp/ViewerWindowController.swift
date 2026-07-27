import AppKit
import ImageviewCore
import UniformTypeIdentifiers

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("ImageviewToolbar")
        static let open = NSToolbarItem.Identifier("open")
        static let previous = NSToolbarItem.Identifier("previous")
        static let next = NSToolbarItem.Identifier("next")
        static let fit = NSToolbarItem.Identifier("fit")
        static let actual = NSToolbarItem.Identifier("actual")
        static let rotateLeft = NSToolbarItem.Identifier("rotateLeft")
        static let rotateRight = NSToolbarItem.Identifier("rotateRight")
        static let flip = NSToolbarItem.Identifier("flip")
        static let crop = NSToolbarItem.Identifier("crop")
        static let flexible = NSToolbarItem.Identifier.flexibleSpace
    }

    private let canvas = ImageCanvasView(frame: .zero)
    private let session = ViewerSession()
    private var cropPanel: CropPanelController?
    private var cropBeforeEditing = NormalizedRect.full

    init(urls: [URL] = []) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Imageview"
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.minSize = NSSize(width: 520, height: 360)
        window.center()
        super.init(window: window)

        window.delegate = self
        window.contentView = canvas
        configureToolbar(for: window)
        configureCallbacks()

        if !urls.isEmpty {
            session.open(urls: urls)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func open(urls: [URL]) {
        session.open(urls: urls)
        showWindow(nil)
    }

    @objc func chooseFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else {
            return
        }
        open(urls: panel.urls)
    }

    @objc func showPrevious(_ sender: Any?) {
        session.move(.previous)
    }

    @objc func showNext(_ sender: Any?) {
        session.move(.next)
    }

    @objc func fitToWindow(_ sender: Any?) {
        canvas.fitToWindow()
    }

    @objc func showActualSize(_ sender: Any?) {
        canvas.showActualSize()
    }

    @objc func rotateLeft(_ sender: Any?) {
        session.rotate(clockwise: false)
    }

    @objc func rotateRight(_ sender: Any?) {
        session.rotate(clockwise: true)
    }

    @objc func flipHorizontal(_ sender: Any?) {
        session.flip(horizontal: true)
    }

    @objc func beginCrop(_ sender: Any?) {
        if let cropPanel {
            cropPanel.showWindow(nil)
            cropPanel.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard session.snapshot.image != nil else {
            NSSound.beep()
            return
        }

        cropBeforeEditing = session.snapshot.recipe.crop
        canvas.beginCrop(cropBeforeEditing)
        let controller = CropPanelController()
        controller.onAspectChanged = { [weak self] aspect in
            self?.canvas.setCropAspect(aspect)
            self?.updateCropPanelSize()
        }
        controller.onPixelSizeChanged = { [weak self] width, height in
            self?.canvas.setCropPixelSize(width: width, height: height)
            self?.updateCropPanelSize()
        }
        controller.onCopy = { [weak self] in
            self?.copyCroppedImage()
        }
        controller.onSaveAs = { [weak self] in
            self?.saveCroppedImageAs()
        }
        controller.onOverwrite = { [weak self] in
            self?.overwriteCurrentImage()
        }
        controller.onCancel = { [weak self] in
            self?.cancelCrop()
        }
        cropPanel = controller
        controller.updatePixelSize(canvas.cropPixelSize())
        controller.showWindow(nil)
        positionCropPanel(controller)
    }

    func windowWillClose(_ notification: Notification) {
        session.cancel()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open, ToolbarID.previous, ToolbarID.next, ToolbarID.fit,
            ToolbarID.actual, ToolbarID.rotateLeft, ToolbarID.rotateRight,
            ToolbarID.flip, ToolbarID.crop, ToolbarID.flexible,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open, ToolbarID.previous, ToolbarID.next, ToolbarID.flexible,
            ToolbarID.fit, ToolbarID.actual, ToolbarID.rotateLeft,
            ToolbarID.rotateRight, ToolbarID.flip, ToolbarID.crop,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarID.open:
            toolbarItem(itemIdentifier, label: "Open", symbol: "folder", action: #selector(chooseFiles(_:)))
        case ToolbarID.previous:
            toolbarItem(itemIdentifier, label: "Previous", symbol: "chevron.left", action: #selector(showPrevious(_:)))
        case ToolbarID.next:
            toolbarItem(itemIdentifier, label: "Next", symbol: "chevron.right", action: #selector(showNext(_:)))
        case ToolbarID.fit:
            toolbarItem(itemIdentifier, label: "Fit", symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fitToWindow(_:)))
        case ToolbarID.actual:
            toolbarItem(itemIdentifier, label: "Actual Size", symbol: "1.magnifyingglass", action: #selector(showActualSize(_:)))
        case ToolbarID.rotateLeft:
            toolbarItem(itemIdentifier, label: "Rotate Left", symbol: "rotate.left", action: #selector(rotateLeft(_:)))
        case ToolbarID.rotateRight:
            toolbarItem(itemIdentifier, label: "Rotate Right", symbol: "rotate.right", action: #selector(rotateRight(_:)))
        case ToolbarID.flip:
            toolbarItem(itemIdentifier, label: "Flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", action: #selector(flipHorizontal(_:)))
        case ToolbarID.crop:
            toolbarItem(itemIdentifier, label: "Crop", symbol: "crop", action: #selector(beginCrop(_:)))
        default:
            nil
        }
    }

    private func configureToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: ToolbarID.toolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    private func configureCallbacks() {
        canvas.onOpenURLs = { [weak self] urls in
            self?.open(urls: urls)
        }
        canvas.onNavigate = { [weak self] forward in
            self?.session.move(forward ? .next : .previous)
        }
        canvas.onCropChanged = { [weak self] crop in
            self?.session.setCrop(crop)
            self?.updateCropPanelSize()
        }
        session.onChange = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        apply(session.snapshot)
    }

    private func apply(_ snapshot: ViewerSession.Snapshot) {
        canvas.image = snapshot.image
        canvas.errorMessage = snapshot.errorMessage
        canvas.isLoading = snapshot.isLoading

        if let current = snapshot.current,
           let position = snapshot.position {
            window?.title = "\(current.url.lastPathComponent) · \(position) / \(snapshot.items.count)"
            window?.representedURL = current.url
        } else {
            window?.title = "Imageview"
            window?.representedURL = nil
        }
    }

    private func toolbarItem(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        symbol: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }

    private func updateCropPanelSize() {
        cropPanel?.updatePixelSize(canvas.cropPixelSize())
    }

    private func positionCropPanel(_ controller: CropPanelController) {
        guard let viewerFrame = window?.frame,
              let panel = controller.window else {
            return
        }
        panel.setFrameTopLeftPoint(
            CGPoint(x: viewerFrame.maxX - panel.frame.width - 16, y: viewerFrame.maxY - 52)
        )
    }

    private func copyCroppedImage() {
        do {
            let image = try session.renderedCurrentImage()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
        } catch {
            presentError(title: "Copy Failed", error: error)
        }
    }

    private func saveCroppedImageAs() {
        guard let source = session.snapshot.current?.url else {
            return
        }
        let defaultFormat = exportFormat(for: source) ?? .png
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent
            + "-cropped."
            + defaultFormat.fileExtension
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let format = exportFormat(for: destination) ?? defaultFormat
        do {
            try session.saveCurrent(
                to: destination,
                format: format,
                metadataPolicy: .preserve
            )
            finishCrop()
        } catch {
            presentError(title: "Save Failed", error: error)
        }
    }

    private func overwriteCurrentImage() {
        guard let source = session.snapshot.current?.url else {
            return
        }
        guard let format = exportFormat(for: source) else {
            presentMessage(
                title: "Cannot Overwrite This Format",
                message: "Use Save As to export JPEG, PNG, TIFF, or HEIC."
            )
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Overwrite Original Image?"
        alert.informativeText = "Imageview validates a temporary file before replacing the original."
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try session.overwriteCurrent(format: format, metadataPolicy: .preserve)
            finishCrop()
        } catch {
            presentError(title: "Overwrite Failed", error: error)
        }
    }

    private func cancelCrop() {
        session.setCrop(cropBeforeEditing)
        finishCrop()
    }

    private func finishCrop() {
        canvas.endCrop()
        cropPanel?.onCancel = nil
        cropPanel?.close()
        cropPanel = nil
    }

    private func exportFormat(for url: URL) -> ExportFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            .jpeg(quality: 0.9)
        case "png":
            .png
        case "tif", "tiff":
            .tiff
        case "heic", "heif":
            .heic(quality: 0.9)
        default:
            nil
        }
    }

    private func presentError(title: String, error: Error) {
        presentMessage(title: title, message: error.localizedDescription)
    }

    private func presentMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
