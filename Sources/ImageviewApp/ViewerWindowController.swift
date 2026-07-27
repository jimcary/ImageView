import AppKit
import ImageviewCore

@MainActor
final class ViewerWindowController:
    NSWindowController,
    NSWindowDelegate,
    NSToolbarDelegate,
    NSMenuDelegate,
    NSMenuItemValidation,
    NSToolbarItemValidation
{
    var onClose: (() -> Void)?
    var onOpenURLsRequested: (([URL]) -> Void)?
    private enum ToolbarID {
        static let toolbar = NSToolbar.Identifier("ImageviewToolbar")
        static let open = NSToolbarItem.Identifier("open")
        static let previous = NSToolbarItem.Identifier("previous")
        static let next = NSToolbarItem.Identifier("next")
        static let previousPage = NSToolbarItem.Identifier("previousPage")
        static let nextPage = NSToolbarItem.Identifier("nextPage")
        static let slideshow = NSToolbarItem.Identifier("slideshow")
        static let fit = NSToolbarItem.Identifier("fit")
        static let actual = NSToolbarItem.Identifier("actual")
        static let rotateLeft = NSToolbarItem.Identifier("rotateLeft")
        static let rotateRight = NSToolbarItem.Identifier("rotateRight")
        static let flip = NSToolbarItem.Identifier("flip")
        static let flipVertical = NSToolbarItem.Identifier("flipVertical")
        static let crop = NSToolbarItem.Identifier("crop")
        static let delete = NSToolbarItem.Identifier("delete")
        static let grid = NSToolbarItem.Identifier("grid")
        static let thumbnails = NSToolbarItem.Identifier("thumbnails")
        static let inspector = NSToolbarItem.Identifier("inspector")
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
    private var cropTransaction: CropTransaction?
    private let openWithMenu = NSMenu()
    private var pinControllers: [PinboardWindowController] = []
    private var ocrTask: Task<Void, Never>?
    private var subjectTask: Task<Void, Never>?
    private var thumbnailHeightConstraint: NSLayoutConstraint?
    private var lastPresentedMediaID: MediaItem.ID?
    private var selectedSortOrder: MediaSortOrder = .name

    var currentURL: URL? {
        session.snapshot.current?.url
    }

    var hasCurrentItem: Bool {
        session.snapshot.current != nil
    }

    var canCommitCrop: Bool {
        guard canvas.isCropMode,
              canvas.hasCropSelection,
              let cropTransaction else {
            return false
        }
        let snapshot = session.snapshot
        return snapshot.subimageCount == 1
            && cropTransaction.matches(
                currentMediaID: snapshot.current?.id,
                decodedMediaID: snapshot.decodedMediaID,
                decodeGeneration: snapshot.decodeGeneration,
                subimageIndex: snapshot.decodedSubimageIndex
            )
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

    @objc func showPreviousPage(_ sender: Any?) {
        session.moveSubimage(-1)
    }

    @objc func showNextPage(_ sender: Any?) {
        session.moveSubimage(1)
    }

    @objc func toggleSlideshow(_ sender: Any?) {
        if canvas.isCropMode {
            cancelCrop(nil)
        }
        session.toggleSlideshow()
    }

    @objc func fitToWindow(_ sender: Any?) {
        canvas.fitToWindow()
    }

    @objc func showActualSize(_ sender: Any?) {
        canvas.showActualSize()
    }

    @objc func deleteCurrent(_ sender: Any?) {
        do {
            try session.moveCurrentToTrash()
        } catch {
            presentError(title: L10n.text("error.delete_failed"), error: error)
        }
    }

    @objc func copyCurrentImage(_ sender: Any?) {
        guard let image = try? session.renderedCurrentImage() else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    @objc func setSortOrder(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let order = sortOrder(for: item.tag) else {
            return
        }
        applySortOrder(order)
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
        if canvas.isCropMode {
            window?.makeFirstResponder(canvas)
            return
        }
        let snapshot = session.snapshot
        guard let current = snapshot.current,
              snapshot.image != nil,
              let decodeGeneration = snapshot.decodeGeneration,
              snapshot.decodedMediaID == current.id,
              let decodedSubimageIndex = snapshot.decodedSubimageIndex else {
            NSSound.beep()
            return
        }
        guard snapshot.subimageCount == 1 else {
            presentMessage(
                title: L10n.text("error.cannot_overwrite_title"),
                message: L10n.text("error.cannot_overwrite_message")
            )
            return
        }

        cropTransaction = CropTransaction(
            mediaID: current.id,
            decodeGeneration: decodeGeneration,
            subimageIndex: decodedSubimageIndex,
            originalRecipe: snapshot.recipe
        )
        canvas.beginCrop()
    }

    @objc func commitCropAndOverwrite(_ sender: Any?) {
        guard canCommitCrop,
              let cropTransaction,
              let source = session.snapshot.current?.url else {
            NSSound.beep()
            return
        }
        guard let format = exportFormat(for: source, quality: 0.9) else {
            presentMessage(
                title: L10n.text("error.cannot_overwrite_title"),
                message: L10n.text("error.cannot_overwrite_message")
            )
            return
        }

        do {
            try session.overwriteCurrent(
                transaction: cropTransaction,
                format: format,
                metadataPolicy: .preserve
            )
            finishCrop()
        } catch {
            presentError(title: L10n.text("error.overwrite_failed"), error: error)
        }
    }

    @objc func cancelCrop(_ sender: Any?) {
        guard canvas.isCropMode else {
            return
        }
        if let cropTransaction {
            session.setRecipe(cropTransaction.originalRecipe)
        }
        finishCrop()
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

    @objc func showCurrentInFinder(_ sender: Any?) {
        guard let url = window?.representedURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func openCurrentInDefaultApp(_ sender: Any?) {
        guard let url = session.snapshot.current?.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openCurrentWithApplication(_ sender: NSMenuItem) {
        guard let imageURL = session.snapshot.current?.url,
              let applicationURL = sender.representedObject as? URL else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [imageURL],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else {
                return
            }
            Task { @MainActor in
                self?.presentError(
                    title: L10n.text("error.open_failed"),
                    error: error
                )
            }
        }
    }

    @objc func setFinderLabel(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              (0...7).contains(item.tag) else {
            return
        }
        applyFinderLabel(item.tag)
    }

    private func applyFinderLabel(_ labelNumber: Int) {
        do {
            try session.setFinderLabel(labelNumber)
        } catch {
            let snapshot = session.snapshot
            inspectorController.update(
                item: snapshot.current,
                properties: snapshot.sourceProperties
            )
            presentError(title: L10n.text("menu.finder_label"), error: error)
        }
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

    @objc func extractSubject(_ sender: Any?) {
        guard SystemCapabilities.subjectExtractionAvailable,
              let image = try? session.renderedCurrentImage() else {
            NSSound.beep()
            return
        }
        guard #available(macOS 14.0, *) else {
            return
        }

        subjectTask?.cancel()
        window?.title = L10n.text("viewer.extracting_subject")
        subjectTask = Task { [weak self] in
            do {
                let extracted = try await SubjectExtractionController().extract(image)
                guard !Task.isCancelled else { return }
                self?.showPin(
                    PinboardWindowController(
                        image: NSImage(cgImage: extracted, size: .zero)
                    )
                )
                if let snapshot = self?.session.snapshot {
                    self?.apply(snapshot)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.presentError(
                    title: L10n.text("error.subject_failed"),
                    error: error
                )
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
        subjectTask?.cancel()
        onClose?()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open, ToolbarID.previous, ToolbarID.next, ToolbarID.fit,
            ToolbarID.previousPage, ToolbarID.nextPage, ToolbarID.slideshow,
            ToolbarID.actual, ToolbarID.rotateLeft, ToolbarID.rotateRight,
            ToolbarID.flip, ToolbarID.flipVertical, ToolbarID.crop, ToolbarID.delete,
            ToolbarID.flexible,
            ToolbarID.grid, ToolbarID.thumbnails, ToolbarID.inspector,
            ToolbarID.ocr,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.open, ToolbarID.previous, ToolbarID.next, ToolbarID.flexible,
            ToolbarID.previousPage, ToolbarID.nextPage, ToolbarID.slideshow,
            ToolbarID.fit, ToolbarID.actual, ToolbarID.rotateLeft,
            ToolbarID.rotateRight, ToolbarID.flip, ToolbarID.flipVertical, ToolbarID.crop,
            ToolbarID.delete,
            ToolbarID.grid, ToolbarID.thumbnails, ToolbarID.inspector,
            ToolbarID.ocr,
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
        case ToolbarID.previousPage:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.previous_page"), symbol: "doc.badge.arrow.up", action: #selector(showPreviousPage(_:)))
        case ToolbarID.nextPage:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.next_page"), symbol: "doc.badge.arrow.down", action: #selector(showNextPage(_:)))
        case ToolbarID.slideshow:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.slideshow"), symbol: "play.rectangle", action: #selector(toggleSlideshow(_:)))
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
        case ToolbarID.delete:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.delete"), symbol: "trash", action: #selector(deleteCurrent(_:)))
        case ToolbarID.grid:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.grid"), symbol: "square.grid.3x3", action: #selector(toggleGrid(_:)))
        case ToolbarID.thumbnails:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.thumbnails"), symbol: "rectangle.bottomthird.inset.filled", action: #selector(toggleThumbnails(_:)))
        case ToolbarID.inspector:
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.info"), symbol: "info.circle", action: #selector(toggleInspector(_:)))
        case ToolbarID.ocr:
            guard SystemCapabilities.ocrAvailable else { return nil }
            return toolbarItem(itemIdentifier, label: L10n.text("toolbar.ocr"), symbol: "text.viewfinder", action: #selector(performOCR(_:)))
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == ToolbarID.delete {
            return session.snapshot.current != nil
        }
        return true
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
        canvas.menu = makeContextMenu()
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
        canvas.onBeginCropRequested = { [weak self] in
            guard let self else {
                return false
            }
            self.beginCrop(nil)
            return self.canvas.isCropMode
        }
        canvas.onCropChanged = { [weak self] crop in
            self?.session.setCrop(crop)
        }
        canvas.onCancelCrop = { [weak self] in
            self?.cancelCrop(nil)
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
            self?.applySortOrder(order)
        }
        inspectorController.onDeleteRequested = { [weak self] in
            self?.deleteCurrent(nil)
        }
        inspectorController.onFinderLabelChanged = { [weak self] labelNumber in
            self?.applyFinderLabel(labelNumber)
        }
        session.onChange = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        session.onFrame = { [weak self] image in
            self?.canvas.present(image, resetViewport: false)
        }
        apply(session.snapshot)
    }

    private func apply(_ snapshot: ViewerSession.Snapshot) {
        if canvas.isCropMode,
           cropTransaction?.matches(
               currentMediaID: snapshot.current?.id,
               decodedMediaID: snapshot.decodedMediaID,
               decodeGeneration: snapshot.decodeGeneration,
               subimageIndex: snapshot.decodedSubimageIndex
           ) != true {
            finishCrop()
        }
        let mediaID = snapshot.current?.id
        canvas.present(
            snapshot.image,
            resetViewport: mediaID != lastPresentedMediaID
        )
        lastPresentedMediaID = mediaID
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
            var title = "\(current.url.lastPathComponent) · \(position) / \(snapshot.items.count)"
            if snapshot.playbackKind == .document {
                title += " · " + String(
                    format: L10n.text("viewer.page_format"),
                    snapshot.subimageIndex + 1,
                    snapshot.subimageCount
                )
            }
            window?.title = title
            window?.representedURL = current.url
        } else {
            window?.title = "Imageview"
            window?.representedURL = nil
        }
        window?.toolbar?.validateVisibleItems()
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

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.setAccessibilityIdentifier("imageCanvasContextMenu")
        menu.addItem(
            contextMenuItem(
                L10n.text("menu.recognize_text"),
                action: #selector(performOCR(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            contextMenuItem(
                L10n.text("menu.actual"),
                action: #selector(showActualSize(_:))
            )
        )
        menu.addItem(
            contextMenuItem(
                L10n.text("menu.fit"),
                action: #selector(fitToWindow(_:))
            )
        )
        menu.addItem(.separator())

        let sortMenu = NSMenu(title: L10n.text("menu.sort"))
        for tag in 0...6 {
            let item = contextMenuItem(
                sortTitle(for: tag),
                action: #selector(setSortOrder(_:))
            )
            item.tag = tag
            sortMenu.addItem(item)
        }
        let sortItem = NSMenuItem(
            title: L10n.text("menu.sort"),
            action: nil,
            keyEquivalent: ""
        )
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)

        let processingMenu = NSMenu(title: L10n.text("menu.image_processing"))
        processingMenu.addItem(
            contextMenuItem(
                L10n.text("toolbar.rotate_left"),
                action: #selector(rotateLeft(_:))
            )
        )
        processingMenu.addItem(
            contextMenuItem(
                L10n.text("toolbar.rotate_right"),
                action: #selector(rotateRight(_:))
            )
        )
        processingMenu.addItem(
            contextMenuItem(
                L10n.text("toolbar.flip"),
                action: #selector(flipHorizontal(_:))
            )
        )
        processingMenu.addItem(
            contextMenuItem(
                L10n.text("toolbar.flip_vertical"),
                action: #selector(flipVertical(_:))
            )
        )
        processingMenu.addItem(.separator())
        processingMenu.addItem(
            contextMenuItem(
                L10n.text("toolbar.crop"),
                action: #selector(beginCrop(_:))
            )
        )
        let processingItem = NSMenuItem(
            title: L10n.text("menu.image_processing"),
            action: nil,
            keyEquivalent: ""
        )
        processingItem.submenu = processingMenu
        menu.addItem(processingItem)

        let labelMenu = NSMenu(title: L10n.text("menu.finder_label"))
        for tag in 0...7 {
            let item = contextMenuItem(
                finderLabelTitle(for: tag),
                action: #selector(setFinderLabel(_:))
            )
            item.tag = tag
            labelMenu.addItem(item)
        }
        let labelItem = NSMenuItem(
            title: L10n.text("menu.finder_label"),
            action: nil,
            keyEquivalent: ""
        )
        labelItem.submenu = labelMenu
        menu.addItem(labelItem)
        menu.addItem(.separator())

        menu.addItem(
            contextMenuItem(
                L10n.text("menu.pin_desktop"),
                action: #selector(pinCurrentImage(_:))
            )
        )
        menu.addItem(
            contextMenuItem(
                L10n.text("inspector.show_finder"),
                action: #selector(showCurrentInFinder(_:))
            )
        )
        menu.addItem(
            contextMenuItem(
                L10n.text("inspector.open_default"),
                action: #selector(openCurrentInDefaultApp(_:))
            )
        )
        openWithMenu.title = L10n.text("menu.open_with")
        openWithMenu.delegate = self
        let openWithItem = NSMenuItem(
            title: L10n.text("menu.open_with"),
            action: nil,
            keyEquivalent: ""
        )
        openWithItem.submenu = openWithMenu
        menu.addItem(openWithItem)
        menu.addItem(.separator())
        menu.addItem(
            contextMenuItem(
                L10n.text("menu.copy"),
                action: #selector(copyCurrentImage(_:))
            )
        )
        menu.addItem(
            contextMenuItem(
                L10n.text("menu.delete"),
                action: #selector(deleteCurrent(_:))
            )
        )
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.submenu === openWithMenu {
            return session.snapshot.current != nil
        }
        if menuItem.action == #selector(setSortOrder(_:)) {
            menuItem.state = menuItem.tag == sortTag(for: selectedSortOrder)
                ? .on
                : .off
            return true
        }
        if menuItem.action == #selector(setFinderLabel(_:)) {
            menuItem.state = menuItem.tag == (session.snapshot.current?.finderLabel ?? 0)
                ? .on
                : .off
        }

        let currentImageActions: [Selector] = [
            #selector(performOCR(_:)),
            #selector(showActualSize(_:)),
            #selector(fitToWindow(_:)),
            #selector(rotateLeft(_:)),
            #selector(rotateRight(_:)),
            #selector(flipHorizontal(_:)),
            #selector(flipVertical(_:)),
            #selector(beginCrop(_:)),
            #selector(setFinderLabel(_:)),
            #selector(pinCurrentImage(_:)),
            #selector(showCurrentInFinder(_:)),
            #selector(openCurrentInDefaultApp(_:)),
            #selector(copyCurrentImage(_:)),
            #selector(deleteCurrent(_:)),
        ]
        if let action = menuItem.action, currentImageActions.contains(action) {
            return session.snapshot.current != nil
        }
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === openWithMenu else {
            return
        }
        menu.removeAllItems()
        guard let imageURL = session.snapshot.current?.url else {
            addEmptyOpenWithItem(to: menu)
            return
        }

        let rows = OpenWithApplications.rows(
            from: NSWorkspace.shared.urlsForApplications(toOpen: imageURL),
            excluding: Bundle.main.bundleURL
        ) {
            FileManager.default.displayName(atPath: $0.path)
        }
        guard !rows.isEmpty else {
            addEmptyOpenWithItem(to: menu)
            return
        }

        for row in rows {
            let item = NSMenuItem(
                title: row.displayName,
                action: #selector(openCurrentWithApplication(_:)),
                keyEquivalent: ""
            )
            let icon = NSWorkspace.shared.icon(forFile: row.url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            item.representedObject = row.url
            item.target = self
            menu.addItem(item)
        }
    }

    private func addEmptyOpenWithItem(to menu: NSMenu) {
        let item = NSMenuItem(
            title: L10n.text("menu.no_compatible_applications"),
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        menu.addItem(item)
    }

    private func contextMenuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func applySortOrder(_ order: MediaSortOrder) {
        selectedSortOrder = order
        gridController.selectSortOrder(order)
        session.setSortOrder(order)
    }

    private func sortOrder(for tag: Int) -> MediaSortOrder? {
        switch tag {
        case 0: .name
        case 1: .extension
        case 2: .creationDate
        case 3: .modificationDate
        case 4: .finderOrder
        case 5: .random
        case 6: .finderLabel
        default: nil
        }
    }

    private func sortTag(for order: MediaSortOrder) -> Int {
        switch order {
        case .name: 0
        case .extension: 1
        case .creationDate: 2
        case .modificationDate: 3
        case .finderOrder: 4
        case .random: 5
        case .finderLabel: 6
        }
    }

    private func sortTitle(for tag: Int) -> String {
        switch tag {
        case 0: L10n.text("sort.name")
        case 1: L10n.text("sort.extension")
        case 2: L10n.text("sort.creation_date")
        case 3: L10n.text("sort.modification_date")
        case 4: L10n.text("sort.finder_order")
        case 5: L10n.text("sort.random")
        case 6: L10n.text("sort.finder_label")
        default: ""
        }
    }

    private func finderLabelTitle(for tag: Int) -> String {
        switch tag {
        case 0: L10n.text("label.no_label")
        case 1: L10n.text("label.gray")
        case 2: L10n.text("label.green")
        case 3: L10n.text("label.purple")
        case 4: L10n.text("label.blue")
        case 5: L10n.text("label.yellow")
        case 6: L10n.text("label.red")
        case 7: L10n.text("label.orange")
        default: ""
        }
    }

    private func finishCrop() {
        canvas.endCrop()
        cropTransaction = nil
    }

    private func exportFormat(for url: URL, quality: Double) -> ExportFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            .jpeg(quality: quality)
        case "png":
            .png
        case "tif", "tiff":
            .tiff
        case "heic":
            .heic(quality: quality)
        case "heif":
            .heif(quality: quality)
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
