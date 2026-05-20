import Foundation

actor Cache {
    private struct Entry {
        let value: Data
        let expiresAt: Date
    }

    static let defaultMaxEntries = 1000

    private let maxEntries: Int
    private var entries: [String: Entry] = [:]
    // keyOrder: least-recently-used at index 0, most-recently-used at last index.
    // Maintained on every get/set so eviction at capacity drops the oldest hit.
    private var keyOrder: [String] = []

    init(maxEntries: Int = Cache.defaultMaxEntries) {
        precondition(maxEntries > 0, "Cache capacity must be positive")
        self.maxEntries = maxEntries
    }

    func get(key: String) -> Data? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > Date() else {
            entries.removeValue(forKey: key)
            removeFromOrder(key)
            return nil
        }
        bumpToMostRecent(key)
        return entry.value
    }

    func set(key: String, value: Data, ttl: TimeInterval) {
        guard ttl > 0 else { return } // TTL 0 = do not cache

        let isUpdate = entries[key] != nil
        entries[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))

        if isUpdate {
            bumpToMostRecent(key)
        } else {
            keyOrder.append(key)
            evictIfNeeded()
        }
    }

    func clear() {
        entries.removeAll()
        keyOrder.removeAll()
    }

    /// Visible for tests: current number of live entries.
    func count() -> Int { entries.count }

    // MARK: - LRU bookkeeping

    private func bumpToMostRecent(_ key: String) {
        removeFromOrder(key)
        keyOrder.append(key)
    }

    private func removeFromOrder(_ key: String) {
        if let idx = keyOrder.firstIndex(of: key) {
            keyOrder.remove(at: idx)
        }
    }

    private func evictIfNeeded() {
        while keyOrder.count > maxEntries {
            let victim = keyOrder.removeFirst()
            entries.removeValue(forKey: victim)
        }
    }
}
