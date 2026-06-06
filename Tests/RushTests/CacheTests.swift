import XCTest
@testable import Rush

final class CacheTests: XCTestCase {
    func testSetAndGet() async {
        let cache = Cache()
        await cache.set(key: "k", value: Data("hello".utf8), ttl: 60)
        let got = await cache.get(key: "k")
        XCTAssertEqual(got, Data("hello".utf8))
    }

    func testExpiry() async {
        let cache = Cache()
        await cache.set(key: "k", value: Data("x".utf8), ttl: 0.05) // 50ms
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let got = await cache.get(key: "k")
        XCTAssertNil(got)
    }

    func testTTLZeroNeverCaches() async {
        let cache = Cache()
        await cache.set(key: "k", value: Data("x".utf8), ttl: 0)
        let got = await cache.get(key: "k")
        XCTAssertNil(got, "TTL 0 means do not cache")
    }

    // MARK: - LRU eviction

    func testEvictsOldestWhenOverCapacity() async {
        let cache = Cache(maxEntries: 3)
        await cache.set(key: "a", value: Data("1".utf8), ttl: 60)
        await cache.set(key: "b", value: Data("2".utf8), ttl: 60)
        await cache.set(key: "c", value: Data("3".utf8), ttl: 60)
        await cache.set(key: "d", value: Data("4".utf8), ttl: 60) // should evict "a"

        let a = await cache.get(key: "a")
        let b = await cache.get(key: "b")
        let c = await cache.get(key: "c")
        let d = await cache.get(key: "d")
        XCTAssertNil(a, "oldest key should be evicted at capacity")
        XCTAssertEqual(b, Data("2".utf8))
        XCTAssertEqual(c, Data("3".utf8))
        XCTAssertEqual(d, Data("4".utf8))
    }

    func testGetBumpsKeyToMostRecent() async {
        let cache = Cache(maxEntries: 3)
        await cache.set(key: "a", value: Data("1".utf8), ttl: 60)
        await cache.set(key: "b", value: Data("2".utf8), ttl: 60)
        await cache.set(key: "c", value: Data("3".utf8), ttl: 60)

        _ = await cache.get(key: "a") // bump "a" to most recent

        await cache.set(key: "d", value: Data("4".utf8), ttl: 60)

        let a = await cache.get(key: "a")
        let b = await cache.get(key: "b")
        XCTAssertEqual(a, Data("1".utf8), "recently-accessed key survives eviction")
        XCTAssertNil(b, "least-recently-used should be evicted")
    }

    func testUpdatingExistingKeyDoesNotEvict() async {
        let cache = Cache(maxEntries: 2)
        await cache.set(key: "a", value: Data("1".utf8), ttl: 60)
        await cache.set(key: "b", value: Data("2".utf8), ttl: 60)
        await cache.set(key: "a", value: Data("1-updated".utf8), ttl: 60)

        let a = await cache.get(key: "a")
        let b = await cache.get(key: "b")
        XCTAssertEqual(a, Data("1-updated".utf8), "existing key updated in place")
        XCTAssertEqual(b, Data("2".utf8), "no eviction on update")
    }

    func testExpiredKeyIsRemovedFromOrderTracking() async {
        // Regression guard: expired key dropped from dict must also drop from keyOrder
        // so capacity accounting stays correct.
        let cache = Cache(maxEntries: 2)
        await cache.set(key: "a", value: Data("1".utf8), ttl: 0.05) // 50ms
        await cache.set(key: "b", value: Data("2".utf8), ttl: 60)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        _ = await cache.get(key: "a") // triggers TTL expiry cleanup

        await cache.set(key: "c", value: Data("3".utf8), ttl: 60)
        await cache.set(key: "d", value: Data("4".utf8), ttl: 60)
        let size = await cache.count()
        XCTAssertEqual(size, 2, "cap must hold even after TTL expiry interleaved with inserts")
    }
}
