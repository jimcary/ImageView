import Foundation

public struct CostCache<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var accessSequence: UInt64
        var isProtected: Bool
    }

    public let costLimit: Int
    public private(set) var totalCost = 0
    private var entries: [Key: Entry] = [:]
    private var sequence: UInt64 = 0

    public init(costLimit: Int) {
        self.costLimit = max(costLimit, 0)
    }

    public mutating func insert(
        _ value: Value,
        for key: Key,
        cost: Int,
        protected: Bool = false
    ) {
        if let existing = entries.removeValue(forKey: key) {
            totalCost -= existing.cost
        }

        sequence &+= 1
        let boundedCost = max(cost, 0)
        entries[key] = Entry(
            value: value,
            cost: boundedCost,
            accessSequence: sequence,
            isProtected: protected
        )
        totalCost += boundedCost
        evictIfNeeded()
    }

    public mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else {
            return nil
        }
        sequence &+= 1
        entry.accessSequence = sequence
        entries[key] = entry
        return entry.value
    }

    public mutating func protect(_ key: Key, _ protected: Bool) {
        guard var entry = entries[key] else {
            return
        }
        entry.isProtected = protected
        entries[key] = entry
        evictIfNeeded()
    }

    public mutating func removeValue(for key: Key) {
        if let entry = entries.removeValue(forKey: key) {
            totalCost -= entry.cost
        }
    }

    public mutating func removeUnprotected() {
        let removableKeys = entries.compactMap { key, entry in
            entry.isProtected ? nil : key
        }
        for key in removableKeys {
            removeValue(for: key)
        }
    }

    private mutating func evictIfNeeded() {
        while totalCost > costLimit {
            guard let oldest = entries
                .filter({ !$0.value.isProtected })
                .min(by: { $0.value.accessSequence < $1.value.accessSequence }) else {
                return
            }
            removeValue(for: oldest.key)
        }
    }
}

public struct DecodeGeneration: Sendable {
    private var current: UInt64 = 0

    public init() {}

    public mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    public mutating func invalidate() {
        current &+= 1
    }

    public func isCurrent(_ generation: UInt64) -> Bool {
        generation == current
    }
}
