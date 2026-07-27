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
func deletingCurrentItemSelectsNearestSurvivor() {
    let original = mediaFixtures(["a.jpg", "b.jpg", "c.jpg"])
    var index = MediaIndex(items: original)
    index.select(id: original[1].id)

    index.replaceItems([original[0], original[2]])

    #expect(index.current?.url.lastPathComponent == "c.jpg")
}

@Test
func navigationNeverIndexesAnEmptyCollection() {
    var index = MediaIndex(items: [])

    #expect(index.move(.next) == nil)
    #expect(index.current == nil)
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
