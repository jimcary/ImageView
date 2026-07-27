import AppKit
import ImageviewCore

@MainActor
final class GridViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((MediaItem.ID) -> Void)?

    private let collectionView = NSCollectionView()
    private let formatPopup = NSPopUpButton()
    private let labelPopup = NSPopUpButton()
    private var allItems: [MediaItem] = []
    private var visibleItems: [MediaItem] = []
    private var selectedID: MediaItem.ID?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1).cgColor

        formatPopup.target = self
        formatPopup.action = #selector(filterChanged(_:))
        labelPopup.addItems(withTitles: [
            L10n.text("label.all"), L10n.text("label.none"), L10n.text("label.gray"),
            L10n.text("label.green"), L10n.text("label.purple"), L10n.text("label.blue"),
            L10n.text("label.yellow"), L10n.text("label.red"), L10n.text("label.orange"),
        ])
        labelPopup.target = self
        labelPopup.action = #selector(filterChanged(_:))

        let controls = NSStackView(views: [
            NSTextField(labelWithString: L10n.text("grid.format")),
            formatPopup,
            NSTextField(labelWithString: L10n.text("grid.label")),
            labelPopup,
        ])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 150)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
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
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    func update(items: [MediaItem], selectedID: MediaItem.ID?) {
        guard allItems.map(\.id) != items.map(\.id) || self.selectedID != selectedID else {
            return
        }
        allItems = items
        self.selectedID = selectedID
        rebuildFormatMenu()
        applyFilter()
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
}
