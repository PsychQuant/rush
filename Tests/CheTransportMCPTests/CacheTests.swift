import XCTest
@testable import CheTransportMCP

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
}
