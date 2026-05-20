import Foundation

actor Cache {
    private struct Entry {
        let value: Data
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]

    func get(key: String) -> Data? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > Date() else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func set(key: String, value: Data, ttl: TimeInterval) {
        guard ttl > 0 else { return } // TTL 0 = do not cache
        entries[key] = Entry(value: value, expiresAt: Date().addingTimeInterval(ttl))
    }

    func clear() {
        entries.removeAll()
    }
}
