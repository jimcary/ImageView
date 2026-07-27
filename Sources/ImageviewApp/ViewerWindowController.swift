import AppKit
import ImageviewCore
import UniformTypeIdentifiers

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var onClose: (() -> Void)?
    var onOpenURLsRequested: (([URL]) -> Void)?
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
        static let flipVertical = NSToolbarItem.Identifier("flipVertical")
        static let crop = NSToolbarItem.Identifier("crop")
        static let grid = NSToolbarItem.Identifier("grid")
        static let thumbnails = NSToolbarItem.Identifier("thumbnails")
        static let inspector = NSToolbarItem.Identifier("inspector")
        static let pin = NSToolbarItem.Identifier("pin")
        static let pastePin = NSToolbarItem.Identifier("pastePin")
        static let ocr = NSToolbarItem.Identifier("ocr")
        static let flexible = NSToolbarItem.Identifier.flexibleSpace
    }

    private let canvas = ImageCanvasView(frame: .zero)
    private let thumbnailStrip = ThumbnailStripView(frame: .zero)
    private let gridController = GridViewController()
    private let inspectorController = InspectorViewController()
    private let centerStack = NSStackView()
    private let splitView = NSSplitView()
    private let session = ViewerSession()
    private var cropPanel: CropPanelController?
    private var cropBeforeEditing = NormalizedRect.full
    private var pinControllers: [PinboardWindowController] = []
    private var ocrTask: Task<Void, Never>?
    private var thumbnailHeightConstraint: NSLayoutConstraint?

    var currentURL: URL? {
        session.snapshot.current?.url
    }

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
        configureContent(for: window)
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
        if let onOpenURLsRequested {
            onOpenURLsRequested(panel.urls)
        } else {
            open(urls: panel.urls)
        }
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

    @objc func flipVertical(_ sender: Any?) {
        session.flip(horizontal: false)
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

    @objc func toggleGrid(_ sender: Any?) {
        gridController.view.isHidden.toggle()
        canvas.isHidden = !gridController.view.isHidden
    }

    @objc func toggleThumbnails(_ sender: Any?) {
        let preferences = PreferencesStore()
        preferences.showsThumbnails.toggle()
        applyPreferences()
    }

    @objc func toggleInspector(_ sender: Any?) {
        inspectorController.view.isHidden.toggle()
        splitView.adjustSubviews()
    }

    @objc func pinCurrentImage(_ sender: Any?) {
        guard let image = try? session.renderedCurrentImage() else {
            NSSound.beep()
            return
        }
        showPin(PinboardWindowController(image: NSImage(cgImage: image, size: .zero)))
    }

    @objc func pinClipboard(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            showPin(PinboardWindowController(image: image))
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            showPin(PinboardWindowController(text: text))
        } else {
            NSSound.beep()
        }
    }

    @objc func performOCR(_ sender: Any?) {
        guard SystemCapabilities.ocrAvailable,
              let image = try? session.renderedCurrentImage() else {
            NSSound.beep()
            return
        }
        ocrTask?.cancel()
        window?.title = L10n.text("viewer.recognizing")
        ocrTask = Task { [weak self] in
            do {
                let text = try await OCRController().recognize(image)
                guard !Task.isCancelled else { return }
                self?.showPin(PinboardWindowController(text: text))
                if let snapshot = self?.session.snapshot {
                    self?.apply(snapshot)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.presentError(title: L10n.text("error.ocr_failed"), error: error)
                if let snapshot = self?.session.snapshot {
                    self?.apply(snapshot)
                }
            }
        }
    }

    @objc func printCurrentImage(_ sender: Any?) {
        guard let image = try? session.renderedCurrentImage() else {
            NSSound.beep()
            return
        }

        let size = NSSize(width: image.width, height: image.height)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter

        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        let operation = NSPrintOperation(view: imageView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    func applyPreferences() {
        let preferences = PreferencesStore()
        thumbnailStrip.setThumbnailSize(preferences.thumbnailSize)
        thumbnailHeightConstraint?.constant = CGFloat(preferences.thumbnailSize + 18)
        thumbnailStrip.isHidden = !preferences.showsThumbnails
        session.applyPreferences()
    }

    func windowWillClose(_ notification: Notification) {
        session.cancel()
        ocrTask?.cancel()
        onClose?()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open, ToolbarID.previous, ToolbarID.next, ToolbarID.fit,
            ToolbarID.actual, ToolbarID.rotateLeft, ToolbarID.rotateRight,
            ToolbarID.flip, ToolbarID.flipVertical, ToolbarID.crop, ToolbarID.flexible,
            ToolbarID.grid, ToolbarID.thumbnails, ToolbarID.inspector,
            ToolbarID.pin, ToolbarID.pastePin, ToolbarID.ocr,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open, ToolbarID.previous, ToolbarID.next, ToolbarID.flexible,
            ToolbarID.fit, ToolbarID.actual, ToolbarID.rotateLeft,
            ToolbarID.rotateRight, ToolbarID.flip, ToolbarID.flipVertical, ToolbarID.crop,
            ToolbarID.grid, ToolbarID.thumbnails, ToolbarID.inspector,
            ToolbarID.pin, ToolbarID.pastePin, ToolbarID.ocr,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarID.open:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.open"), symbol: "folder", action: #selector(chooseFiles(_:)))
        case ToolbarID.previous:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.previous"), symbol: "chevron.left", action: #selector(showPrevious(_:)))
        case ToolbarID.next:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.next"), symbol: "chevron.right", action: #selector(showNext(_:)))
        case ToolbarID.fit:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.fit"), symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fitToWindow(_:)))
        case ToolbarID.actual:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.actual"), symbol: "1.magnifyingglass", action: #selector(showActualSize(_:)))
        case ToolbarID.rotateLeft:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.rotate_left"), symbol: "rotate.left", action: #selector(rotateLeft(_:)))
        case ToolbarID.rotateRight:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.rotate_right"), symbol: "rotate.right", action: #selector(rotateRight(_:)))
        case ToolbarID.flip:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.flip"), symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", action: #selector(flipHorizontal(_:)))
        case ToolbarID.flipVertical:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.flip_vertical"), symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", action: #selector(flipVertical(_:)))
        case ToolbarID.crop:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.crop"), symbol: "crop", action: #selector(beginCrop(_:)))
        case ToolbarID.grid:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.grid"), symbol: "square.grid.3x3", action: #selector(toggleGrid(_:)))
        case ToolbarID.thumbnails:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.thumbnails"), symbol: "rectangle.bottomthird.inset.filled", action: #selector(toggleThumbnails(_:)))
        case ToolbarID.inspector:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.info"), symbol: "info.circle", action: #selector(toggleInspector(_:)))
        case ToolbarID.pin:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.pin"), symbol: "pin", action: #selector(pinCurrentImage(_:)))
        case ToolbarID.pastePin:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.pin_clipboard"), symbol: "doc.on.clipboard", action: #selector(pinClipboard(_:)))
        case ToolbarID.ocr:
            guard SystemCapabilities.ocrAvailable else { return nil }
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.ocr"), symbol: "text.viewfinder", action: #selector(performOCR(_:)))
        default:
            return nil
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

    private func configureContent(for window: NSWindow) {
        let contentArea = NSView()
        for view in [canvas, gridController.view] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentArea.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
                view.topAnchor.constraint(equalTo: contentArea.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            ])
        }
        gridController.view.isHidden = true

        thumbnailStrip.translatesAutoresizingMaskIntoConstraints = false
        let thumbnailHeightConstraint = thumbnailStrip.heightAnchor.constraint(equalToConstant: 104)
        thumbnailHeightConstraint.isActive = true
        self.thumbnailHeightConstraint = thumbnailHeightConstraint
        centerStack.orientation = .vertical
        centerStack.spacing = 0
        centerStack.addArrangedSubview(contentArea)
        centerStack.addArrangedSubview(thumbnailStrip)

        inspectorController.view.isHidden = true
        inspectorController.view.translatesAutoresizingMaskIntoConstraints = false
        inspectorController.view.widthAnchor.constraint(equalToConstant: 300).isActive = true

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(centerStack)
        splitView.addArrangedSubview(inspectorController.view)
        window.contentView = splitView
        applyPreferences()
    }

    private func configureCallbacks() {
        canvas.onOpenURLs = { [weak self] urls in
            guard let self else { return }
            if let onOpenURLsRequested {
                onOpenURLsRequested(urls)
            } else {
                open(urls: urls)
            }
        }
        canvas.onNavigate = { [weak self] forward in
            self?.session.move(forward ? .next : .previous)
        }
        canvas.onCropChanged = { [weak self] crop in
            self?.session.setCrop(crop)
            self?.updateCropPanelSize()
        }
        thumbnailStrip.onSelect = { [weak self] id in
            self?.session.select(id: id)
        }
        gridController.onSelect = { [weak self] id in
            self?.session.select(id: id)
            self?.gridController.view.isHidden = true
            self?.canvas.isHidden = false
        }
        gridController.onSortChanged = { [weak self] order in
            self?.session.setSortOrder(order)
        }
        inspectorController.onTrash = { [weak self] in
            self?.session.refreshCurrentFolder()
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
        thumbnailStrip.update(items: snapshot.items, selectedID: snapshot.current?.id)
        gridController.update(items: snapshot.items, selectedID: snapshot.current?.id)
        inspectorController.update(
            item: snapshot.current,
            properties: snapshot.sourceProperties
        )

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
            presentError(title: L10n.text("error.copy_failed"), error: error)
        }
    }

    private func saveCroppedImageAs() {
        guard let source = session.snapshot.current?.url else {
            return
        }
        let quality = cropPanel?.exportQuality ?? 0.9
        let metadataPolicy = cropPanel?.metadataPolicy ?? .preserve
        let defaultFormat = exportFormat(for: source, quality: quality) ?? .png
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent
            + "-cropped."
            + defaultFormat.fileExtension
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let format = exportFormat(for: destination, quality: quality) ?? defaultFormat
        do {
            try session.saveCurrent(
                to: destination,
                format: format,
                metadataPolicy: metadataPolicy
            )
            finishCrop()
        } catch {
            presentError(title: L10n.text("error.save_failed"), error: error)
        }
    }

    private func overwriteCurrentImage() {
        guard let source = session.snapshot.current?.url else {
            return
        }
        let quality = cropPanel?.exportQuality ?? 0.9
        let metadataPolicy = cropPanel?.metadataPolicy ?? .preserve
        guard let format = exportFormat(for: source, quality: quality) else {
            presentMessage(
                title: L10n.text("error.cannot_overwrite_title"),
                message: L10n.text("error.cannot_overwrite_message")
            )
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("confirm.overwrite_title")
        alert.informativeText = L10n.text("confirm.overwrite_message")
        alert.addButton(withTitle: L10n.text("confirm.overwrite_button"))
        alert.addButton(withTitle: L10n.text("action.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try session.overwriteCurrent(format: format, metadataPolicy: metadataPolicy)
            finishCrop()
        } catch {
            presentError(title: L10n.text("error.overwrite_failed"), error: error)
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

    private func exportFormat(for url: URL, quality: Double) -> ExportFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            .jpeg(quality: quality)
        case "png":
            .png
        case "tif", "tiff":
            .tiff
        case "heic", "heif":
            .heic(quality: quality)
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

    private func showPin(_ controller: PinboardWindowController) {
        pinControllers.removeAll { $0.window == nil }
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.pinControllers.removeAll { $0 === controller }
        }
        pinControllers.append(controller)
        controller.window?.alphaValue = PreferencesStore().pinOpacity
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.orderFrontRegardless()
    }
}
