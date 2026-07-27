import AppKit
import ImageviewCore

@MainActor
final class ThumbnailStripView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((MediaItem.ID) -> Void)?

    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private var items: [MediaItem] = []
    private var thumbnailSize = AppPreferences.defaultThumbnailSize

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: thumbnailSize, height: thumbnailSize)
        flowLayout.minimumInteritemSpacing = 6
        flowLayout.sectionInset = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [NSColor.windowBackgroundColor.withAlphaComponent(0.96)]
        collectionView.register(
            MediaCollectionItem.self,
            forItemWithIdentifier: MediaCollectionItem.identifier
        )

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(items: [MediaItem], selectedID: MediaItem.ID?) {
        let needsReload = self.items.map(\.id) != items.map(\.id)
        self.items = items
        if needsReload {
            collectionView.reloadData()
        }
        guard let selectedID,
              let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            collectionView.selectionIndexPaths = []
            return
        }
        let path = IndexPath(item: selectedIndex, section: 0)
        collectionView.selectionIndexPaths = [path]
        collectionView.scrollToItems(at: [path], scrollPosition: .centeredHorizontally)
    }

    func setThumbnailSize(_ size: Int) {
        let bounded = min(max(size, 48), 320)
        guard thumbnailSize != bounded else {
            return
        }
        thumbnailSize = bounded
        flowLayout.itemSize = NSSize(width: bounded, height: bounded)
        flowLayout.invalidateLayout()
        collectionView.reloadData()
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        1
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        items.count
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
        item.configure(with: items[indexPath.item], maxPixelSize: thumbnailSize * 2)
        return item
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let index = indexPaths.first?.item, items.indices.contains(index) else {
            return
        }
        onSelect?(items[index].id)
    }
}
