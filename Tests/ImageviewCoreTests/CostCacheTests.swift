import Testing
@testable import ImageviewCore

@Test
func cacheEvictsLeastRecentlyUsedNonProtectedEntryByCost() {
    var cache = CostCache<String, Int>(costLimit: 10)
    cache.insert(1, for: "current", cost: 6, protected: true)
    cache.insert(2, for: "old", cost: 4)
    cache.insert(3, for: "new", cost: 4)

    #expect(cache.value(for: "old") == nil)
    #expect(cache.value(for: "current") == 1)
    #expect(cache.value(for: "new") == 3)
    #expect(cache.totalCost == 10)
}

@Test
func readingCacheValueUpdatesRecency() {
    var cache = CostCache<String, Int>(costLimit: 2)
    cache.insert(1, for: "a", cost: 1)
    cache.insert(2, for: "b", cost: 1)
    _ = cache.value(for: "a")
    cache.insert(3, for: "c", cost: 1)

    #expect(cache.value(for: "a") == 1)
    #expect(cache.value(for: "b") == nil)
}

@Test
func memoryPressureKeepsProtectedEntriesOnly() {
    var cache = CostCache<String, Int>(costLimit: 20)
    cache.insert(1, for: "current", cost: 6, protected: true)
    cache.insert(2, for: "prefetch", cost: 6)

    cache.removeUnprotected()

    #expect(cache.value(for: "current") == 1)
    #expect(cache.value(for: "prefetch") == nil)
}
