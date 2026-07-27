import Foundation

public enum NavigationDirection: Sendable {
    case previous
    case next
    case first
    case last
    case random
}

public enum MediaSortOrder: Sendable {
    case name
    case `extension`
    case creationDate
    case modificationDate
    case finderOrder
    case random
    case finderLabel
}

public enum MediaItemSorter {
    public static func sorted(
        _ items: [MediaItem],
        by order: MediaSortOrder
    ) -> [MediaItem] {
        if case .random = order {
            return items.shuffled()
        }

        return items.sorted { left, right in
            let comparison: ComparisonResult
            switch order {
            case .name:
                comparison = compare(
                    left.url.deletingPathExtension().lastPathComponent,
                    right.url.deletingPathExtension().lastPathComponent
                )
            case .extension:
                comparison = compare(left.url.pathExtension, right.url.pathExtension)
            case .creationDate:
                comparison = compare(left.createdAt, right.createdAt)
            case .modificationDate:
                comparison = compare(left.modifiedAt, right.modifiedAt)
            case .finderOrder:
                comparison = compare(left.finderOrder, right.finderOrder)
            case .finderLabel:
                comparison = compare(left.finderLabel ?? -1, right.finderLabel ?? -1)
            case .random:
                comparison = .orderedSame
            }

            if comparison == .orderedSame {
                return compare(left.url.lastPathComponent, right.url.lastPathComponent) == .orderedAscending
            }
            return comparison == .orderedAscending
        }
    }

    private static func compare(_ left: String, _ right: String) -> ComparisonResult {
        left.localizedStandardCompare(right)
    }

    private static func compare<T: Comparable>(_ left: T?, _ right: T?) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?):
            return compare(left, right)
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right {
            return .orderedAscending
        }
        if left > right {
            return .orderedDescending
        }
        return .orderedSame
    }
}

public struct MediaFilter: Sendable {
    public let includedExtensions: Set<String>
    public let excludedExtensions: Set<String>
    public let finderLabels: Set<Int>
    public let includesUnlabeled: Bool

    public init(
        includedExtensions: Set<String> = [],
        excludedExtensions: Set<String> = [],
        finderLabels: Set<Int> = [],
        includesUnlabeled: Bool = true
    ) {
        self.includedExtensions = Set(includedExtensions.map { $0.lowercased() })
        self.excludedExtensions = Set(excludedExtensions.map { $0.lowercased() })
        self.finderLabels = finderLabels
        self.includesUnlabeled = includesUnlabeled
    }

    public func apply(to items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            let pathExtension = item.url.pathExtension.lowercased()
            guard !excludedExtensions.contains(pathExtension) else {
                return false
            }
            guard includedExtensions.isEmpty || includedExtensions.contains(pathExtension) else {
                return false
            }

            if let label = item.finderLabel {
                return finderLabels.isEmpty || finderLabels.contains(label)
            }
            return includesUnlabeled
        }
    }
}

public struct MediaIndex: Sendable {
    public private(set) var items: [MediaItem]
    public private(set) var currentIndex: Int?

    public var current: MediaItem? {
        guard let currentIndex, items.indices.contains(currentIndex) else {
            return nil
        }
        return items[currentIndex]
    }

    public init(items: [MediaItem]) {
        self.items = items
        currentIndex = items.isEmpty ? nil : 0
    }

    public mutating func select(id: MediaItem.ID) {
        currentIndex = items.firstIndex { $0.id == id }
    }

    public mutating func replaceItems(
        _ replacement: [MediaItem],
        preserving identifier: MediaItem.ID? = nil
    ) {
        let selectedID = identifier ?? current?.id
        let previousIndex = currentIndex
        items = replacement

        if let selectedID,
           let matchingIndex = replacement.firstIndex(where: { $0.id == selectedID }) {
            currentIndex = matchingIndex
        } else if replacement.isEmpty {
            currentIndex = nil
        } else {
            currentIndex = min(previousIndex ?? 0, replacement.count - 1)
        }
    }

    @discardableResult
    public mutating func move(
        _ direction: NavigationDirection,
        wraps: Bool = true
    ) -> MediaItem? {
        guard !items.isEmpty else {
            currentIndex = nil
            return nil
        }

        let index = currentIndex ?? 0
        switch direction {
        case .first:
            currentIndex = 0
        case .last:
            currentIndex = items.count - 1
        case .previous:
            currentIndex = index > 0 ? index - 1 : (wraps ? items.count - 1 : 0)
        case .next:
            currentIndex = index + 1 < items.count ? index + 1 : (wraps ? 0 : items.count - 1)
        case .random:
            currentIndex = Int.random(in: items.indices)
        }
        return current
    }
}
