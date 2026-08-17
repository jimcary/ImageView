import Foundation
import Testing
@testable import ImageviewCore

@Test
func replacingItemsPreservesCurrentIdentifier() {
    let original = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: original)
    index.select(id: original[1].id)

    index.replaceItems([original[2], original[1]])

    #expect(index.current?.url.lastPathComponent == "b.jpg")
}

@Test
func replacingCurrentMetadataAfterResortPreservesSelection() {
    let original = [
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/a.jpg"),
            resourceIdentifier: "a",
            finderLabel: 1
        ),
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/b.jpg"),
            resourceIdentifier: "b",
            finderLabel: 2
        ),
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/c.jpg"),
            resourceIdentifier: "c",
            finderLabel: 3
        ),
    ]
    var index = MediaIndex(items: original)
    index.select(id: "b")
    let relabeled = MediaItem(
        url: original[1].url,
        resourceIdentifier: original[1].resourceIdentifier,
        finderLabel: 7
    )
    let replacement = MediaItemSorter.sorted(
        [original[0], relabeled, original[2]],
        by: .finderLabel
    )

    index.replaceItems(replacement, preserving: "b")

    #expect(index.items.map(\.id) == ["a", "c", "b"])
    #expect(index.current?.id == "b")
}

@Test
func replacingCurrentItemPreservesExplicitListAndPosition() {
    let original = mediaFixtures(["search-a.jpg", "search-b.jpg", "search-c.jpg"])
    var index = MediaIndex(items: original)
    index.select(id: original[1].id)
    let refreshed = MediaItem(
        url: original[1].url,
        resourceIdentifier: "replacement-id",
        fileSize: 999
    )

    let replaced = index.replaceCurrent(with: refreshed)

    #expect(replaced?.id == original[1].id)
    #expect(index.items.map(\.url.lastPathComponent) == [
        "search-a.jpg", "search-b.jpg", "search-c.jpg",
    ])
    #expect(index.currentIndex == 1)
    #expect(index.current?.id == "replacement-id")
}

@Test
func deletingCurrentItemSelectsNearestSurvivor() {
    let original = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: original)
    index.select(id: original[1].id)

    index.replaceItems([original[0], original[2]])

    #expect(index.current?.url.lastPathComponent == "c.jpg")
}

@Test
func removingMiddleItemSelectsTheFollowingItem() {
    let items = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: items)
    index.select(id: items[1].id)

    let removed = index.removeCurrent()

    #expect(removed?.url.lastPathComponent == "b.jpg")
    #expect(index.current?.url.lastPathComponent == "c.jpg")
}

@Test
func removingLastItemSelectsThePreviousItem() {
    let items = mediaFixtures(["a.jpg", "b.jpg"])
    var index = MediaIndex(items: items)
    index.select(id: items[1].id)

    _ = index.removeCurrent()

    #expect(index.current?.url.lastPathComponent == "a.jpg")
}

@Test
func navigationNeverIndexesAnEmptyCollection() {
    var index = MediaIndex(items: [])

    #expect(index.move(.next) == nil)
    #expect(index.current == nil)
}

@Test
func forwardNavigationWrapsFromFinalToFirst() {
    let items = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: items)
    index.select(id: items[2].id)

    #expect(index.move(.next)?.id == items[0].id)
    #expect(index.currentIndex == 0)
}

@Test
func navigationHandlesBackwardSingleAndEmptyCollections() {
    let items = mediaFixtures(["a.jpg", "b.jpg"])
    var index = MediaIndex(items: items)
    #expect(index.move(.previous)?.id == items[1].id)

    var single = MediaIndex(items: [items[0]])
    #expect(single.move(.next)?.id == items[0].id)

    var empty = MediaIndex(items: [])
    #expect(empty.move(.next) == nil)
}

@Test
func mediaSortingSupportsNameExtensionDatesFinderOrderAndLabels() {
    let items = [
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/z.png"),
            resourceIdentifier: "z",
            createdAt: Date(timeIntervalSince1970: 30),
            modifiedAt: Date(timeIntervalSince1970: 10),
            finderLabel: 3,
            finderOrder: 0
        ),
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/a.jpg"),
            resourceIdentifier: "a",
            createdAt: Date(timeIntervalSince1970: 20),
            modifiedAt: Date(timeIntervalSince1970: 30),
            finderLabel: nil,
            finderOrder: 2
        ),
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/m.gif"),
            resourceIdentifier: "m",
            createdAt: Date(timeIntervalSince1970: 10),
            modifiedAt: Date(timeIntervalSince1970: 20),
            finderLabel: 1,
            finderOrder: 1
        ),
    ]

    #expect(MediaItemSorter.sorted(items, by: .name).map(\.id) == ["a", "m", "z"])
    #expect(MediaItemSorter.sorted(items, by: .extension).map(\.id) == ["m", "a", "z"])
    #expect(MediaItemSorter.sorted(items, by: .creationDate).map(\.id) == ["m", "a", "z"])
    #expect(MediaItemSorter.sorted(items, by: .modificationDate).map(\.id) == ["z", "m", "a"])
    #expect(MediaItemSorter.sorted(items, by: .finderOrder).map(\.id) == ["z", "m", "a"])
    #expect(MediaItemSorter.sorted(items, by: .finderLabel).map(\.id) == ["a", "m", "z"])
}

@Test
func mediaFilterCombinesExtensionAndFinderLabelRules() {
    let items = [
        MediaItem(url: URL(fileURLWithPath: "/tmp/a.jpg"), resourceIdentifier: "a", finderLabel: nil),
        MediaItem(url: URL(fileURLWithPath: "/tmp/b.png"), resourceIdentifier: "b", finderLabel: 2),
        MediaItem(url: URL(fileURLWithPath: "/tmp/c.gif"), resourceIdentifier: "c", finderLabel: 3),
    ]
    let filter = MediaFilter(
        includedExtensions: ["jpg", "png"],
        excludedExtensions: ["gif"],
        finderLabels: [2],
        includesUnlabeled: true
    )

    #expect(filter.apply(to: items).map(\.id) == ["a", "b"])
}

private func mediaFixtures(_ names: [String]) -> [MediaItem] {
    names.enumerated().map { offset, name in
        MediaItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            resourceIdentifier: "fixture-\(offset)"
        )
    }
}
