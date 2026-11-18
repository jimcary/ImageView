import AppKit
import ImageviewCore

@MainActor
final class GridViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((MediaItem.ID) -> Void)?
    var onSortChanged: ((MediaSortOrder) -> Void)?

    private let collectionView = NSCollectionView()
    private let controlsScrollView = NSScrollView()
    private var controls: NSStackView?
    private let formatPopup = NSPopUpButton()
    private let labelPopup = NSPopUpButton()
    private let sortPopup = NSPopUpButton()
    private let sortOrders: [MediaSortOrder] = [
        .name, .extension, .creationDate, .modificationDate,
        .finderOrder, .random, .finderLabel,
    ]
    private var allItems: [MediaItem] = []
    private var visibleItems: [MediaItem] = []
    private var selectedID: MediaItem.ID?

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .contentBackground
        root.blendingMode = .withinWindow

        formatPopup.addItem(withTitle: L10n.text("grid.all_formats"))
        formatPopup.target = self
        formatPopup.action = #selector(filterChanged(_:))
        labelPopup.addItems(withTitles: [
            L10n.text("label.all"), L10n.text("label.none"), L10n.text("label.gray"),
            L10n.text("label.green"), L10n.text("label.purple"), L10n.text("label.blue"),
            L10n.text("label.yellow"), L10n.text("label.red"), L10n.text("label.orange"),
        ])
        labelPopup.target = self
        labelPopup.action = #selector(filterChanged(_:))
        sortPopup.addItems(withTitles: sortOrders.map(sortTitle))
        sortPopup.target = self
        sortPopup.action = #selector(sortChanged(_:))

        let controls = NSStackView(views: [
            NSTextField(labelWithString: L10n.text("grid.sort")),
            sortPopup,
            NSTextField(labelWithString: L10n.text("grid.format")),
            formatPopup,
            NSTextField(labelWithString: L10n.text("grid.label")),
            labelPopup,
        ])
        controls.orientation = .horizontal
        controls.spacing = 10
        controls.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        self.controls = controls
        controlsScrollView.documentView = controls
        controlsScrollView.hasHorizontalScroller = true
        controlsScrollView.autohidesScrollers = true
        controlsScrollView.drawsBackground = false
        controlsScrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controlsScrollView)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 150)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            MediaCollectionItem.self,
            forItemWithIdentifier: MediaCollectionItem.identifier
        )

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            controlsScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            controlsScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            controlsScrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            controlsScrollView.heightAnchor.constraint(equalToConstant: 34),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: controlsScrollView.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let controls else { return }
        controls.frame = NSRect(
            x: 0, y: 0,
            width: max(controls.fittingSize.width, controlsScrollView.contentSize.width),
            height: controlsScrollView.contentSize.height
        )
    }

    func update(items: [MediaItem], selectedID: MediaItem.ID?) {
        guard allItems != items || self.selectedID != selectedID else {
            return
        }
        allItems = items
        self.selectedID = selectedID
        rebuildFormatMenu()
        applyFilter()
    }

    func selectSortOrder(_ order: MediaSortOrder) {
        let index: Int
        switch order {
        case .name: index = 0
        case .extension: index = 1
        case .creationDate: index = 2
        case .modificationDate: index = 3
        case .finderOrder: index = 4
        case .random: index = 5
        case .finderLabel: index = 6
        }
        sortPopup.selectItem(at: index)
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        visibleItems.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard let item = collectionView.makeItem(
            withIdentifier: MediaCollectionItem.identifier,
            for: indexPath
        ) as? MediaCollectionItem else {
            return NSCollectionViewItem()
        }
        item.configure(with: visibleItems[indexPath.item], maxPixelSize: 300)
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let index = indexPaths.first?.item, visibleItems.indices.contains(index) else {
            return
        }
        onSelect?(visibleItems[index].id)
    }

    @objc private func filterChanged(_ sender: Any?) {
        applyFilter()
    }

    @objc private func sortChanged(_ sender: Any?) {
        guard sortOrders.indices.contains(sortPopup.indexOfSelectedItem) else {
            return
        }
        onSortChanged?(sortOrders[sortPopup.indexOfSelectedItem])
    }

    private func rebuildFormatMenu() {
        let selected = formatPopup.titleOfSelectedItem
        let formats = Set(allItems.map { $0.url.pathExtension.lowercased() })
            .filter { !$0.isEmpty }
            .sorted()
        formatPopup.removeAllItems()
        formatPopup.addItem(withTitle: L10n.text("grid.all_formats"))
        formatPopup.addItems(withTitles: formats.map { $0.uppercased() })
        if let selected, formatPopup.itemTitles.contains(selected) {
            formatPopup.selectItem(withTitle: selected)
        }
    }

    private func applyFilter() {
        let selectedExtension = formatPopup.indexOfSelectedItem > 0
            ? formatPopup.titleOfSelectedItem?.lowercased()
            : nil
        let labelSelection = labelPopup.indexOfSelectedItem
        visibleItems = allItems.filter { item in
            let extensionMatches = selectedExtension == nil
                || item.url.pathExtension.lowercased() == selectedExtension
            let labelMatches: Bool
            if labelSelection == 0 {
                labelMatches = true
            } else if labelSelection == 1 {
                labelMatches = item.finderLabel == nil || item.finderLabel == 0
            } else {
                labelMatches = item.finderLabel == labelSelection - 1
            }
            return extensionMatches && labelMatches
        }
        collectionView.reloadData()
        guard let selectedID,
              let index = visibleItems.firstIndex(where: { $0.id == selectedID }) else {
            collectionView.selectionIndexPaths = []
            return
        }
        collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
    }

    private func sortTitle(_ order: MediaSortOrder) -> String {
        switch order {
        case .name: L10n.text("sort.name")
        case .extension: L10n.text("sort.extension")
        case .creationDate: L10n.text("sort.creation_date")
        case .modificationDate: L10n.text("sort.modification_date")
        case .finderOrder: L10n.text("sort.finder_order")
        case .random: L10n.text("sort.random")
        case .finderLabel: L10n.text("sort.finder_label")
        }
    }
}
