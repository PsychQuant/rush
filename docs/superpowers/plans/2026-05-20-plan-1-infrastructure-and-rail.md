# Plan 1: Infrastructure + Rail Tools

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working `che-transport-mcp` Swift MCP server with TDX OAuth2 authentication, in-memory TTL cache, and 5 Rail tools (台鐵 / 高鐵 / 各捷運與輕軌). After this plan, the MCP can answer 找班次 and 即時誤點 queries for all rail systems.

**Architecture:** Swift native MCP, modelled after `che-ical-mcp`. TDX OAuth2 client_credentials flow → in-memory bearer token. Cache layer (actor-based) with three TTL tiers (24h / 1h / 0s). Tool implementations call `TDXClient.fetch(endpoint:cacheTTL:)` and convert to MCP responses.

**Tech Stack:** Swift 5.9+, MCP swift-sdk 0.12+, URLSession, Keychain Services, XCTest, Make.

**Spec reference:** `che-transport-mcp/docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md`

---

## Working directory

All paths below are relative to `/Users/che/Developer/che-mcps/che-transport-mcp/`.

Reference repo for patterns: `/Users/che/Developer/che-mcps/che-ical-mcp/`.

---

## Task 1: Initialize Swift package and MCP SDK dependency

**Files:**
- Create: `Package.swift`
- Create: `Sources/CheTransportMCP/main.swift` (stub)
- Create: `Tests/CheTransportMCPTests/SmokeTest.swift`

- [ ] **Step 1: Create repo and init**

```bash
mkdir -p /Users/che/Developer/che-mcps/che-transport-mcp
cd /Users/che/Developer/che-mcps/che-transport-mcp
git init
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CheTransportMCP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.0"))
    ],
    targets: [
        .executableTarget(
            name: "CheTransportMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/CheTransportMCP",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CheTransportMCP/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "CheTransportMCPTests",
            dependencies: ["CheTransportMCP"],
            path: "Tests/CheTransportMCPTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 3: Create minimal stub main.swift**

```swift
// Sources/CheTransportMCP/main.swift
import Foundation
import MCP

print("CheTransportMCP boot — replaced in Task 9")
```

- [ ] **Step 4: Create minimal Info.plist**

```xml
<!-- Sources/CheTransportMCP/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.checheng.CheTransportMCP</string>
    <key>CFBundleName</key>
    <string>CheTransportMCP</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
</dict>
</plist>
```

- [ ] **Step 5: Create smoke test**

```swift
// Tests/CheTransportMCPTests/SmokeTest.swift
import XCTest

final class SmokeTest: XCTestCase {
    func testPackageBuilds() {
        XCTAssertTrue(true, "Package compiles if this test runs")
    }
}
```

- [ ] **Step 6: Create empty fixtures dir**

```bash
mkdir -p Tests/CheTransportMCPTests/Fixtures
touch Tests/CheTransportMCPTests/Fixtures/.gitkeep
```

- [ ] **Step 7: Build and run test**

```bash
swift build
swift test --filter SmokeTest
```

Expected: `Test Suite 'SmokeTest' passed`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "feat: init swift package with MCP SDK dependency"
```

---

## Task 2: Project metadata files

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `Sources/CheTransportMCP/Version.swift`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.DS_Store
.build/
.swiftpm/
Package.resolved
*.xcodeproj/
DerivedData/
*.log
mcpb/server/CheTransportMCP
mcpb/*.mcpb
```

- [ ] **Step 2: Write `LICENSE`** (MIT)

```text
MIT License

Copyright (c) 2026 Che Cheng

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write `Version.swift`**

```swift
// Sources/CheTransportMCP/Version.swift
import Foundation

enum AppVersion {
    static let version = "0.1.0"
    static let versionString = "CheTransportMCP \(version)"
    static let helpMessage = """
    \(versionString)

    USAGE:
      CheTransportMCP                 Run MCP server on stdio
      CheTransportMCP --version       Print version
      CheTransportMCP --help          Print this help
      CheTransportMCP --check-auth    Verify TDX credentials in keychain

    SETUP:
      Run `make setup-tdx` once to register TDX credentials.
    """
}
```

- [ ] **Step 4: Verify build**

```bash
swift build
```

Expected: builds without warnings.

- [ ] **Step 5: Commit**

```bash
git add .gitignore LICENSE Sources/CheTransportMCP/Version.swift
git commit -m "chore: add LICENSE, gitignore, Version metadata"
```

---

## Task 3: Cache layer (TTL-based actor)

**Files:**
- Create: `Sources/CheTransportMCP/Cache.swift`
- Create: `Tests/CheTransportMCPTests/CacheTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CheTransportMCPTests/CacheTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter CacheTests
```

Expected: FAIL — `Cache` type not found.

- [ ] **Step 3: Implement Cache**

```swift
// Sources/CheTransportMCP/Cache.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter CacheTests
```

Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CheTransportMCP/Cache.swift Tests/CheTransportMCPTests/CacheTests.swift
git commit -m "feat: add actor-based TTL cache layer"
```

---

## Task 4: Auth layer (Keychain credentials)

**Files:**
- Create: `Sources/CheTransportMCP/Auth.swift`
- Create: `Tests/CheTransportMCPTests/AuthTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Tests/CheTransportMCPTests/AuthTests.swift
import XCTest
@testable import CheTransportMCP

final class AuthTests: XCTestCase {
    let testService = "che-transport-tdx-test"

    override func tearDown() async throws {
        try? Auth.delete(service: testService)
    }

    func testWriteAndRead() throws {
        try Auth.save(service: testService, account: "client_id", value: "abc123")
        let got = try Auth.read(service: testService, account: "client_id")
        XCTAssertEqual(got, "abc123")
    }

    func testReadMissingThrows() {
        XCTAssertThrowsError(try Auth.read(service: testService, account: "nope"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AuthTests
```

Expected: FAIL — `Auth` not found.

- [ ] **Step 3: Implement Auth**

```swift
// Sources/CheTransportMCP/Auth.swift
import Foundation
import Security

enum AuthError: Error, LocalizedError {
    case itemNotFound
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "TDX credentials missing. Run: make setup-tdx"
        case .keychainError(let status):
            return "Keychain error (OSStatus \(status))"
        }
    }
}

enum Auth {
    static let defaultService = "che-transport-tdx"

    static func save(service: String = defaultService, account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.keychainError(status) }
    }

    static func read(service: String = defaultService, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw AuthError.itemNotFound }
            throw AuthError.keychainError(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AuthError.itemNotFound
        }
        return value
    }

    static func delete(service: String = defaultService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychainError(status)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter AuthTests
```

Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CheTransportMCP/Auth.swift Tests/CheTransportMCPTests/AuthTests.swift
git commit -m "feat: add Keychain-backed credential storage"
```

---

## Task 5: TDXClient — OAuth2 token exchange

**Files:**
- Create: `Sources/CheTransportMCP/TDXClient.swift`
- Create: `Tests/CheTransportMCPTests/TDXClientTests.swift`
- Create: `Tests/CheTransportMCPTests/Fixtures/oauth_response.json`

- [ ] **Step 1: Add OAuth fixture**

```json
{
  "access_token": "eyJhbGciOi...",
  "expires_in": 86400,
  "token_type": "Bearer"
}
```

Save as `Tests/CheTransportMCPTests/Fixtures/oauth_response.json`.

- [ ] **Step 2: Write failing test (parser only)**

```swift
// Tests/CheTransportMCPTests/TDXClientTests.swift
import XCTest
@testable import CheTransportMCP

final class TDXClientTests: XCTestCase {
    func testParseOAuthResponse() throws {
        let url = Bundle.module.url(forResource: "oauth_response", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let token = try TDXClient.parseTokenResponse(data)
        XCTAssertEqual(token.accessToken, "eyJhbGciOi...")
        XCTAssertEqual(token.expiresIn, 86400)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
swift test --filter TDXClientTests
```

Expected: FAIL — `TDXClient` not found.

- [ ] **Step 4: Implement TDXClient.swift (OAuth parser only)**

```swift
// Sources/CheTransportMCP/TDXClient.swift
import Foundation

struct TDXToken: Codable {
    let accessToken: String
    let expiresIn: Int
    let issuedAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case issuedAt
    }

    var expiresAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(expiresIn - 60)) // refresh 60s early
    }

    var isExpired: Bool { Date() >= expiresAt }
}

enum TDXError: Error, LocalizedError {
    case authFailed(String)
    case rateLimited
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "TDX auth failed: \(msg). Run: make setup-tdx"
        case .rateLimited: return "TDX rate limit exceeded; retry in 60s"
        case .http(let code, let msg): return "TDX HTTP \(code): \(msg)"
        case .decoding(let msg): return "TDX response format changed: \(msg). Please file an issue."
        case .network(let msg): return "Network error: \(msg). Check connection."
        }
    }
}

actor TDXClient {
    static let tokenEndpoint = URL(string: "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token")!
    static let apiBase = URL(string: "https://tdx.transportdata.tw/api/basic/")!

    private var cachedToken: TDXToken?

    static func parseTokenResponse(_ data: Data) throws -> TDXToken {
        struct Raw: Decodable {
            let access_token: String
            let expires_in: Int
        }
        do {
            let raw = try JSONDecoder().decode(Raw.self, from: data)
            return TDXToken(accessToken: raw.access_token, expiresIn: raw.expires_in, issuedAt: Date())
        } catch {
            throw TDXError.decoding(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
swift test --filter TDXClientTests/testParseOAuthResponse
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CheTransportMCP/TDXClient.swift Tests/CheTransportMCPTests/TDXClientTests.swift Tests/CheTransportMCPTests/Fixtures/oauth_response.json
git commit -m "feat: TDX OAuth token response parser"
```

---

## Task 6: TDXClient — HTTP fetch with bearer + 429 retry

**Files:**
- Modify: `Sources/CheTransportMCP/TDXClient.swift`
- Modify: `Tests/CheTransportMCPTests/TDXClientTests.swift`

- [ ] **Step 1: Add cache key derivation test**

```swift
// Append to TDXClientTests.swift
func testCacheKeyDerivation() {
    let key1 = TDXClient.cacheKey(path: "/v3/Rail/TRA/Station", queryItems: [
        URLQueryItem(name: "$top", value: "10"),
        URLQueryItem(name: "$format", value: "JSON")
    ])
    let key2 = TDXClient.cacheKey(path: "/v3/Rail/TRA/Station", queryItems: [
        URLQueryItem(name: "$format", value: "JSON"),
        URLQueryItem(name: "$top", value: "10")
    ])
    XCTAssertEqual(key1, key2, "Cache key must be order-independent")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter TDXClientTests/testCacheKeyDerivation
```

Expected: FAIL — `cacheKey` not defined.

- [ ] **Step 3: Add cacheKey + fetch methods**

Append to `Sources/CheTransportMCP/TDXClient.swift`:

```swift
extension TDXClient {
    static func cacheKey(path: String, queryItems: [URLQueryItem]) -> String {
        let sorted = queryItems.sorted { $0.name < $1.name }
        let qs = sorted.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        return "\(path)?\(qs)"
    }
}

extension TDXClient {
    func ensureToken() async throws -> TDXToken {
        if let token = cachedToken, !token.isExpired { return token }

        let clientId = try Auth.read(account: "client_id")
        let clientSecret = try Auth.read(account: "client_secret")

        var req = URLRequest(url: Self.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=client_credentials&client_id=\(clientId)&client_secret=\(clientSecret)"
        req.httpBody = Data(body.utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TDXError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TDXError.network("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TDXError.authFailed("HTTP \(http.statusCode)")
        }

        let token = try Self.parseTokenResponse(data)
        cachedToken = token
        return token
    }

    func fetch(path: String, queryItems: [URLQueryItem] = [], cacheTTL: TimeInterval, cache: Cache) async throws -> Data {
        let key = Self.cacheKey(path: path, queryItems: queryItems)

        if cacheTTL > 0, let cached = await cache.get(key: key) {
            return cached
        }

        // Build URL
        var comps = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = queryItems
        if !items.contains(where: { $0.name == "$format" }) {
            items.append(URLQueryItem(name: "$format", value: "JSON"))
        }
        comps.queryItems = items
        let url = comps.url!

        let data = try await performRequest(url: url, attempt: 1)
        await cache.set(key: key, value: data, ttl: cacheTTL)
        return data
    }

    private func performRequest(url: URL, attempt: Int) async throws -> Data {
        let token = try await ensureToken()
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TDXError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TDXError.network("non-HTTP response")
        }

        if http.statusCode == 429 {
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                return try await performRequest(url: url, attempt: attempt + 1)
            }
            throw TDXError.rateLimited
        }
        if http.statusCode == 401 {
            cachedToken = nil
            throw TDXError.authFailed("HTTP 401")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TDXError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return data
    }
}
```

- [ ] **Step 4: Run unit test to verify**

```bash
swift test --filter TDXClientTests/testCacheKeyDerivation
```

Expected: PASS.

- [ ] **Step 5: Run full test suite (should not break previous tests)**

```bash
swift test
```

Expected: all unit tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CheTransportMCP/TDXClient.swift Tests/CheTransportMCPTests/TDXClientTests.swift
git commit -m "feat: TDX HTTP client with bearer auth, cache, and 429 retry"
```

---

## Task 7: MCP server skeleton with CLI flags

**Files:**
- Modify: `Sources/CheTransportMCP/main.swift`
- Create: `Sources/CheTransportMCP/Server.swift`

- [ ] **Step 1: Replace main.swift with CLI flag handling**

```swift
// Sources/CheTransportMCP/main.swift
import Foundation
import MCP

@main
struct CheTransportMCPMain {
    static func main() async {
        let args = CommandLine.arguments

        if args.contains("--version") || args.contains("-v") {
            print(AppVersion.versionString)
            return
        }
        if args.contains("--help") || args.contains("-h") {
            print(AppVersion.helpMessage)
            return
        }
        if args.contains("--check-auth") {
            await runCheckAuth()
            return
        }

        await TransportServer.run()
    }

    static func runCheckAuth() async {
        do {
            _ = try Auth.read(account: "client_id")
            _ = try Auth.read(account: "client_secret")
            let client = TDXClient()
            _ = try await client.ensureToken()
            print("✓ TDX credentials valid")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("✗ \(msg)\n".utf8))
            exit(1)
        }
    }
}
```

- [ ] **Step 2: Create Server.swift skeleton**

```swift
// Sources/CheTransportMCP/Server.swift
import Foundation
import MCP

enum TransportServer {
    static func run() async {
        let server = Server(
            name: "che-transport-mcp",
            version: AppVersion.version,
            capabilities: .init(tools: .init())
        )

        let cache = Cache()
        let client = TDXClient()

        // Register Rail tools (Tasks 11-15 will populate)
        await RailTools.register(server: server, client: client, cache: cache)

        let transport = StdioTransport()
        do {
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("Server error: \(msg)\n".utf8))
            exit(1)
        }
    }
}
```

- [ ] **Step 3: Create stub RailTools.swift to satisfy compile**

```swift
// Sources/CheTransportMCP/Tools/RailTools.swift
import Foundation
import MCP

enum RailTools {
    static func register(server: Server, client: TDXClient, cache: Cache) async {
        // populated in Tasks 11-15
    }
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

Expected: builds.

- [ ] **Step 5: Run --version**

```bash
swift run CheTransportMCP --version
```

Expected output: `CheTransportMCP 0.1.0`

- [ ] **Step 6: Run --help**

```bash
swift run CheTransportMCP --help
```

Expected: prints help message including `--check-auth` flag.

- [ ] **Step 7: Commit**

```bash
git add Sources/CheTransportMCP/main.swift Sources/CheTransportMCP/Server.swift Sources/CheTransportMCP/Tools/RailTools.swift
git commit -m "feat: MCP server skeleton with --version/--help/--check-auth flags"
```

---

## Task 8: setup-tdx.sh interactive credentials script

**Files:**
- Create: `scripts/setup-tdx.sh`
- Create: `Makefile`

- [ ] **Step 1: Write setup script**

```bash
#!/usr/bin/env bash
# scripts/setup-tdx.sh
set -euo pipefail

SERVICE="che-transport-tdx"

echo "TDX credentials setup for che-transport-mcp"
echo "Register first at: https://tdx.transportdata.tw/register"
echo ""

read -p "TDX client_id: " CLIENT_ID
read -s -p "TDX client_secret: " CLIENT_SECRET
echo ""

# Save to keychain via the binary
BIN="${BIN:-.build/debug/CheTransportMCP}"
if [ ! -x "$BIN" ]; then
    echo "Building debug binary..."
    swift build
fi

# Save credentials by invoking a helper subcommand we'll add; for now use security directly.
security delete-generic-password -s "$SERVICE" -a "client_id" 2>/dev/null || true
security delete-generic-password -s "$SERVICE" -a "client_secret" 2>/dev/null || true
security add-generic-password -s "$SERVICE" -a "client_id" -w "$CLIENT_ID" -U
security add-generic-password -s "$SERVICE" -a "client_secret" -w "$CLIENT_SECRET" -U

echo ""
echo "Verifying credentials by hitting TDX..."
if "$BIN" --check-auth; then
    echo "Setup complete."
else
    echo "Setup failed verification. Check credentials and retry."
    exit 1
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/setup-tdx.sh
```

- [ ] **Step 3: Write minimal Makefile**

```makefile
# Makefile
.PHONY: build test setup-tdx check-auth clean

build:
	swift build

test:
	swift test

setup-tdx:
	@bash scripts/setup-tdx.sh

check-auth: build
	@.build/debug/CheTransportMCP --check-auth

clean:
	swift package clean
	rm -rf .build
```

- [ ] **Step 4: Build to confirm**

```bash
make build
```

Expected: builds.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-tdx.sh Makefile
git commit -m "feat: add setup-tdx interactive script and Makefile"
```

---

## Task 9: Rail data models

**Files:**
- Create: `Sources/CheTransportMCP/Models/RailModels.swift`
- Create: `Tests/CheTransportMCPTests/Fixtures/rail_station.json`
- Create: `Tests/CheTransportMCPTests/Fixtures/rail_timetable.json`
- Create: `Tests/CheTransportMCPTests/RailModelsTests.swift`

- [ ] **Step 1: Add station fixture**

```json
[
  {
    "StationID": "1000",
    "StationName": { "Zh_tw": "臺北", "En": "Taipei" },
    "StationPosition": { "PositionLat": 25.0478, "PositionLon": 121.5170 }
  },
  {
    "StationID": "1020",
    "StationName": { "Zh_tw": "板橋", "En": "Banqiao" },
    "StationPosition": { "PositionLat": 25.0144, "PositionLon": 121.4633 }
  }
]
```

Save as `Tests/CheTransportMCPTests/Fixtures/rail_station.json`.

- [ ] **Step 2: Add timetable fixture (abridged)**

```json
[
  {
    "TrainInfo": {
      "TrainNo": "152",
      "TrainTypeName": { "Zh_tw": "自強號", "En": "Tze-Chiang" }
    },
    "StopTimes": [
      {
        "StationID": "1000",
        "StationName": { "Zh_tw": "臺北", "En": "Taipei" },
        "DepartureTime": "07:12"
      },
      {
        "StationID": "1020",
        "StationName": { "Zh_tw": "板橋", "En": "Banqiao" },
        "ArrivalTime": "07:23",
        "DepartureTime": "07:24"
      }
    ]
  }
]
```

Save as `Tests/CheTransportMCPTests/Fixtures/rail_timetable.json`.

- [ ] **Step 3: Write failing parser test**

```swift
// Tests/CheTransportMCPTests/RailModelsTests.swift
import XCTest
@testable import CheTransportMCP

final class RailModelsTests: XCTestCase {
    func testParseStations() throws {
        let url = Bundle.module.url(forResource: "rail_station", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let stations = try JSONDecoder().decode([RailStation].self, from: data)
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations[0].stationID, "1000")
        XCTAssertEqual(stations[0].stationName.zhTw, "臺北")
    }

    func testParseTimetable() throws {
        let url = Bundle.module.url(forResource: "rail_timetable", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let trains = try JSONDecoder().decode([RailODFare].self, from: data)
        XCTAssertEqual(trains.count, 1)
        XCTAssertEqual(trains[0].trainInfo.trainNo, "152")
        XCTAssertEqual(trains[0].stopTimes.count, 2)
    }
}
```

- [ ] **Step 4: Run to verify fail**

```bash
swift test --filter RailModelsTests
```

Expected: FAIL — types not defined.

- [ ] **Step 5: Implement models**

```swift
// Sources/CheTransportMCP/Models/RailModels.swift
import Foundation

struct LocalizedName: Codable {
    let zhTw: String?
    let en: String?

    enum CodingKeys: String, CodingKey {
        case zhTw = "Zh_tw"
        case en = "En"
    }
}

struct RailPosition: Codable {
    let positionLat: Double
    let positionLon: Double

    enum CodingKeys: String, CodingKey {
        case positionLat = "PositionLat"
        case positionLon = "PositionLon"
    }
}

struct RailStation: Codable {
    let stationID: String
    let stationName: LocalizedName
    let stationPosition: RailPosition?

    enum CodingKeys: String, CodingKey {
        case stationID = "StationID"
        case stationName = "StationName"
        case stationPosition = "StationPosition"
    }
}

struct RailTrainInfo: Codable {
    let trainNo: String
    let trainTypeName: LocalizedName?

    enum CodingKeys: String, CodingKey {
        case trainNo = "TrainNo"
        case trainTypeName = "TrainTypeName"
    }
}

struct RailStopTime: Codable {
    let stationID: String
    let stationName: LocalizedName
    let arrivalTime: String?
    let departureTime: String?

    enum CodingKeys: String, CodingKey {
        case stationID = "StationID"
        case stationName = "StationName"
        case arrivalTime = "ArrivalTime"
        case departureTime = "DepartureTime"
    }
}

struct RailODFare: Codable {
    let trainInfo: RailTrainInfo
    let stopTimes: [RailStopTime]

    enum CodingKeys: String, CodingKey {
        case trainInfo = "TrainInfo"
        case stopTimes = "StopTimes"
    }
}

struct RailLiveTrain: Codable {
    let trainNo: String
    let stationID: String?
    let delayTime: Int?

    enum CodingKeys: String, CodingKey {
        case trainNo = "TrainNo"
        case stationID = "StationID"
        case delayTime = "DelayTime"
    }
}

enum RailSystem: String, CaseIterable, Codable {
    case TRA, THSR, TRTC, TYMC, KRTC, TMRT, NTDLRT, KLRT

    var displayName: String {
        switch self {
        case .TRA: return "台鐵"
        case .THSR: return "高鐵"
        case .TRTC: return "台北捷運"
        case .TYMC: return "桃園捷運"
        case .KRTC: return "高雄捷運"
        case .TMRT: return "台中捷運"
        case .NTDLRT: return "新北捷運"
        case .KLRT: return "高雄輕軌"
        }
    }

    var apiPath: String {
        switch self {
        case .TRA: return "v3/Rail/TRA"
        case .THSR: return "v3/Rail/THSR"
        case .TRTC: return "v2/Rail/Metro/TRTC"
        case .TYMC: return "v2/Rail/Metro/TYMC"
        case .KRTC: return "v2/Rail/Metro/KRTC"
        case .TMRT: return "v2/Rail/Metro/TMRT"
        case .NTDLRT: return "v2/Rail/Metro/NTDLRT"
        case .KLRT: return "v2/Rail/Metro/KLRT"
        }
    }
}
```

- [ ] **Step 6: Run test to verify pass**

```bash
swift test --filter RailModelsTests
```

Expected: 2 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CheTransportMCP/Models/ Tests/CheTransportMCPTests/Fixtures/rail_*.json Tests/CheTransportMCPTests/RailModelsTests.swift
git commit -m "feat: Rail data models with TDX schema decoding"
```

---

## Task 10: rail_list_systems tool

**Files:**
- Modify: `Sources/CheTransportMCP/Tools/RailTools.swift`
- Create: `Tests/CheTransportMCPTests/RailToolsTests.swift`

- [ ] **Step 1: Write test**

```swift
// Tests/CheTransportMCPTests/RailToolsTests.swift
import XCTest
@testable import CheTransportMCP

final class RailToolsTests: XCTestCase {
    func testListSystemsReturnsAllEight() {
        let systems = RailTools.listSystems()
        XCTAssertEqual(systems.count, 8)
        XCTAssertTrue(systems.contains { $0["code"] == "TRA" })
        XCTAssertTrue(systems.contains { $0["code"] == "KLRT" })
    }
}
```

- [ ] **Step 2: Run to verify fail**

```bash
swift test --filter RailToolsTests
```

Expected: FAIL — `listSystems` missing.

- [ ] **Step 3: Implement listSystems + register**

Replace `Sources/CheTransportMCP/Tools/RailTools.swift`:

```swift
// Sources/CheTransportMCP/Tools/RailTools.swift
import Foundation
import MCP

enum RailTools {
    static func register(server: Server, client: TDXClient, cache: Cache) async {
        await registerListSystems(server: server)
    }

    static func listSystems() -> [[String: String]] {
        RailSystem.allCases.map { sys in
            ["code": sys.rawValue, "name": sys.displayName]
        }
    }

    static func registerListSystems(server: Server) async {
        let tool = Tool(
            name: "rail_list_systems",
            description: "列出此 MCP 支援的所有鐵路 system 代碼（TRA, THSR, 各捷運與輕軌）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "additionalProperties": .bool(false)
            ])
        )
        await server.registerTool(tool) { _ in
            let systems = Self.listSystems()
            let data = try JSONSerialization.data(withJSONObject: ["systems": systems])
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .text(json)
        }
    }
}
```

NOTE: the precise MCP swift-sdk API (`Tool`, `inputSchema`, `registerTool`) may need adjustment to actual 0.12 API. Reference `che-ical-mcp/Sources/CheICalMCP/Server.swift` for exact signatures before writing tests. If `registerTool` is different, mirror the existing pattern.

- [ ] **Step 4: Run test**

```bash
swift test --filter RailToolsTests/testListSystemsReturnsAllEight
```

Expected: PASS.

- [ ] **Step 5: Build full project**

```bash
swift build
```

Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add Sources/CheTransportMCP/Tools/RailTools.swift Tests/CheTransportMCPTests/RailToolsTests.swift
git commit -m "feat(rail): rail_list_systems tool"
```

---

## Task 11: rail_search_stations tool

**Files:**
- Modify: `Sources/CheTransportMCP/Tools/RailTools.swift`
- Modify: `Tests/CheTransportMCPTests/RailToolsTests.swift`

- [ ] **Step 1: Write fuzzy-match unit test**

Append to `RailToolsTests.swift`:

```swift
func testFuzzyMatchStations() {
    let stations = [
        RailStation(stationID: "1000", stationName: LocalizedName(zhTw: "臺北", en: "Taipei"), stationPosition: nil),
        RailStation(stationID: "1020", stationName: LocalizedName(zhTw: "板橋", en: "Banqiao"), stationPosition: nil),
        RailStation(stationID: "1080", stationName: LocalizedName(zhTw: "新竹", en: "Hsinchu"), stationPosition: nil)
    ]
    let matches = RailTools.fuzzyMatch(query: "台北", in: stations)
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].stationID, "1000", "台北 should match 臺北")
}

func testFuzzyMatchMultipleResults() {
    let stations = [
        RailStation(stationID: "R10", stationName: LocalizedName(zhTw: "中山", en: "Zhongshan"), stationPosition: nil),
        RailStation(stationID: "G14", stationName: LocalizedName(zhTw: "中山國中", en: "Zhongshan JHS"), stationPosition: nil)
    ]
    let matches = RailTools.fuzzyMatch(query: "中山", in: stations)
    XCTAssertEqual(matches.count, 2, "Both stations contain 中山")
}
```

- [ ] **Step 2: Run test to verify fail**

```bash
swift test --filter RailToolsTests/testFuzzyMatchStations
```

Expected: FAIL — `fuzzyMatch` missing.

- [ ] **Step 3: Implement fuzzyMatch and registration**

Add to `RailTools.swift`:

```swift
extension RailTools {
    static func fuzzyMatch(query: String, in stations: [RailStation]) -> [RailStation] {
        let normalizedQuery = query
            .replacingOccurrences(of: "台", with: "臺")
            .lowercased()
        return stations.filter { station in
            let zh = (station.stationName.zhTw ?? "").replacingOccurrences(of: "台", with: "臺").lowercased()
            let en = (station.stationName.en ?? "").lowercased()
            return zh.contains(normalizedQuery) || en.contains(normalizedQuery)
        }
    }

    static func registerSearchStations(server: Server, client: TDXClient, cache: Cache) async {
        let tool = Tool(
            name: "rail_search_stations",
            description: "依名稱（中或英）模糊搜尋鐵路站點，回傳所有匹配站點與其所屬 system。「中山」會回傳多個 system 的同名站。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string"), "description": .string("站名關鍵字")]),
                    "system": .object(["type": .string("string"), "description": .string("選填，限制特定 system（TRA/THSR/TRTC/TYMC/KRTC/TMRT/NTDLRT/KLRT）")])
                ]),
                "required": .array([.string("query")]),
                "additionalProperties": .bool(false)
            ])
        )
        await server.registerTool(tool) { params in
            let query = params["query"]?.stringValue ?? ""
            let systemFilter: [RailSystem] = {
                if let s = params["system"]?.stringValue, let sys = RailSystem(rawValue: s) {
                    return [sys]
                }
                return RailSystem.allCases
            }()

            var allMatches: [[String: Any]] = []
            for sys in systemFilter {
                let data = try await client.fetch(
                    path: "\(sys.apiPath)/Station",
                    cacheTTL: 86400,
                    cache: cache
                )
                // TRA wraps in {Stations: [...]}, metro returns array directly; handle both
                let stations = Self.decodeStationList(data: data)
                let matches = Self.fuzzyMatch(query: query, in: stations)
                for m in matches {
                    allMatches.append([
                        "system": sys.rawValue,
                        "station_id": m.stationID,
                        "name_zh": m.stationName.zhTw ?? "",
                        "name_en": m.stationName.en ?? ""
                    ])
                }
            }

            let json = try JSONSerialization.data(withJSONObject: ["matches": allMatches])
            return .text(String(data: json, encoding: .utf8) ?? "{}")
        }
    }

    static func decodeStationList(data: Data) -> [RailStation] {
        // Try wrapped form first (TRA v3): { "Stations": [...] }
        struct Wrapped: Codable { let Stations: [RailStation] }
        if let wrapped = try? JSONDecoder().decode(Wrapped.self, from: data) {
            return wrapped.Stations
        }
        // Fall back to bare array
        return (try? JSONDecoder().decode([RailStation].self, from: data)) ?? []
    }
}
```

Update `register`:

```swift
static func register(server: Server, client: TDXClient, cache: Cache) async {
    await registerListSystems(server: server)
    await registerSearchStations(server: server, client: client, cache: cache)
}
```

- [ ] **Step 4: Run unit tests**

```bash
swift test --filter RailToolsTests
```

Expected: all RailTools tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CheTransportMCP/Tools/RailTools.swift Tests/CheTransportMCPTests/RailToolsTests.swift
git commit -m "feat(rail): rail_search_stations with fuzzy match and 臺/台 normalization"
```

---

## Task 12: rail_find_trains tool

**Files:**
- Modify: `Sources/CheTransportMCP/Tools/RailTools.swift`
- Modify: `Tests/CheTransportMCPTests/RailToolsTests.swift`

- [ ] **Step 1: Write date validation test**

```swift
func testValidateDateAccepts() {
    XCTAssertNoThrow(try RailTools.validateDate("2026-05-20"))
}

func testValidateDateRejects() {
    XCTAssertThrowsError(try RailTools.validateDate("2026/5/20"))
    XCTAssertThrowsError(try RailTools.validateDate("not-a-date"))
}
```

- [ ] **Step 2: Run test to verify fail**

```bash
swift test --filter RailToolsTests/testValidateDate
```

Expected: FAIL.

- [ ] **Step 3: Implement validateDate + registerFindTrains**

Append to `RailTools.swift`:

```swift
extension RailTools {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        return f
    }()

    static func validateDate(_ s: String) throws -> String {
        guard dateFormatter.date(from: s) != nil else {
            throw TDXError.decoding("Invalid date '\(s)'. Use ISO format YYYY-MM-DD.")
        }
        return s
    }

    static func registerFindTrains(server: Server, client: TDXClient, cache: Cache) async {
        let tool = Tool(
            name: "rail_find_trains",
            description: "依起站、迄站、日期查詢班次。回傳該日從 from 到 to 的所有班次（含車種與時刻）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "from": .object(["type": .string("string"), "description": .string("起站 station_id（由 rail_search_stations 取得）")]),
                    "to": .object(["type": .string("string")]),
                    "date": .object(["type": .string("string"), "description": .string("YYYY-MM-DD（Asia/Taipei）")]),
                    "system": .object(["type": .string("string"), "description": .string("TRA / THSR")])
                ]),
                "required": .array([.string("from"), .string("to"), .string("date"), .string("system")]),
                "additionalProperties": .bool(false)
            ])
        )
        await server.registerTool(tool) { params in
            let from = params["from"]?.stringValue ?? ""
            let to = params["to"]?.stringValue ?? ""
            let date = try Self.validateDate(params["date"]?.stringValue ?? "")
            let sysCode = params["system"]?.stringValue ?? ""
            guard let sys = RailSystem(rawValue: sysCode) else {
                throw TDXError.decoding("Invalid system '\(sysCode)'. Use rail_list_systems.")
            }

            let path = "\(sys.apiPath)/DailyTrainTimetable/OD/\(from)/to/\(to)/\(date)"
            let data = try await client.fetch(
                path: path,
                cacheTTL: 3600,
                cache: cache
            )

            // Strip TDX wrapper if present and return raw to LLM
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .text(json)
        }
    }
}
```

Update `register`:

```swift
static func register(server: Server, client: TDXClient, cache: Cache) async {
    await registerListSystems(server: server)
    await registerSearchStations(server: server, client: client, cache: cache)
    await registerFindTrains(server: server, client: client, cache: cache)
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RailToolsTests
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CheTransportMCP/Tools/RailTools.swift Tests/CheTransportMCPTests/RailToolsTests.swift
git commit -m "feat(rail): rail_find_trains tool with date validation"
```

---

## Task 13: rail_status_train tool

**Files:**
- Modify: `Sources/CheTransportMCP/Tools/RailTools.swift`

- [ ] **Step 1: Add registration**

```swift
extension RailTools {
    static func registerStatusTrain(server: Server, client: TDXClient, cache: Cache) async {
        let tool = Tool(
            name: "rail_status_train",
            description: "查特定列車的即時誤點與位置。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "train_no": .object(["type": .string("string")]),
                    "system": .object(["type": .string("string"), "description": .string("TRA / THSR")])
                ]),
                "required": .array([.string("train_no"), .string("system")]),
                "additionalProperties": .bool(false)
            ])
        )
        await server.registerTool(tool) { params in
            let trainNo = params["train_no"]?.stringValue ?? ""
            guard let sys = RailSystem(rawValue: params["system"]?.stringValue ?? ""),
                  sys == .TRA || sys == .THSR else {
                throw TDXError.decoding("system must be TRA or THSR for live train status")
            }

            let path = "\(sys.apiPath)/TrainLiveBoard/Train/\(trainNo)"
            let data = try await client.fetch(
                path: path,
                cacheTTL: 0, // 即時 — 不 cache
                cache: cache
            )
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .text(json)
        }
    }
}
```

Update `register` to include it.

- [ ] **Step 2: Build and run all tests**

```bash
swift test
```

Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/CheTransportMCP/Tools/RailTools.swift
git commit -m "feat(rail): rail_status_train tool (TRA/THSR live)"
```

---

## Task 14: rail_status_station tool

**Files:**
- Modify: `Sources/CheTransportMCP/Tools/RailTools.swift`

- [ ] **Step 1: Add registration**

```swift
extension RailTools {
    static func registerStatusStation(server: Server, client: TDXClient, cache: Cache) async {
        let tool = Tool(
            name: "rail_status_station",
            description: "查特定站點近期到站列車（含誤點）。預設視窗 60 分鐘。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "station_id": .object(["type": .string("string")]),
                    "system": .object(["type": .string("string"), "description": .string("TRA / THSR")]),
                    "window_min": .object(["type": .string("integer"), "description": .string("時間視窗（分鐘），預設 60")])
                ]),
                "required": .array([.string("station_id"), .string("system")]),
                "additionalProperties": .bool(false)
            ])
        )
        await server.registerTool(tool) { params in
            let stationID = params["station_id"]?.stringValue ?? ""
            guard let sys = RailSystem(rawValue: params["system"]?.stringValue ?? ""),
                  sys == .TRA || sys == .THSR else {
                throw TDXError.decoding("system must be TRA or THSR for live station status")
            }

            let path = "\(sys.apiPath)/StationLiveBoard/Station/\(stationID)"
            let data = try await client.fetch(
                path: path,
                cacheTTL: 0,
                cache: cache
            )
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return .text(json)
        }
    }
}
```

Update `register` to include it.

- [ ] **Step 2: Build and test**

```bash
swift test
```

Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/CheTransportMCP/Tools/RailTools.swift
git commit -m "feat(rail): rail_status_station tool"
```

---

## Task 15: Integration test scaffolding (XCTSkip on missing creds)

**Files:**
- Create: `Tests/CheTransportMCPTests/RailIntegrationTests.swift`

- [ ] **Step 1: Write integration test that skips when no credentials**

```swift
// Tests/CheTransportMCPTests/RailIntegrationTests.swift
import XCTest
@testable import CheTransportMCP

final class RailIntegrationTests: XCTestCase {
    private func skipIfNoCredentials() throws {
        do {
            _ = try Auth.read(account: "client_id")
            _ = try Auth.read(account: "client_secret")
        } catch {
            throw XCTSkip("TDX credentials not in keychain. Run: make setup-tdx")
        }
    }

    func testListSystemsLocal() async {
        let systems = RailTools.listSystems()
        XCTAssertEqual(systems.count, 8, "Local sanity check, no credentials needed")
    }

    func testTRAStationFetchLive() async throws {
        try skipIfNoCredentials()
        let client = TDXClient()
        let cache = Cache()
        let data = try await client.fetch(
            path: "v3/Rail/TRA/Station",
            cacheTTL: 86400,
            cache: cache
        )
        XCTAssertGreaterThan(data.count, 100, "Expected non-trivial response")
        let stations = RailTools.decodeStationList(data: data)
        XCTAssertGreaterThan(stations.count, 100, "TRA has 200+ stations")
    }

    func testTHSRSearchTaipeiLive() async throws {
        try skipIfNoCredentials()
        let client = TDXClient()
        let cache = Cache()
        let data = try await client.fetch(
            path: "v3/Rail/THSR/Station",
            cacheTTL: 86400,
            cache: cache
        )
        let stations = RailTools.decodeStationList(data: data)
        let matches = RailTools.fuzzyMatch(query: "台北", in: stations)
        XCTAssertFalse(matches.isEmpty, "Should find Taipei THSR station")
    }
}
```

- [ ] **Step 2: Run test (will skip if no creds)**

```bash
swift test --filter RailIntegrationTests
```

Expected: `testListSystemsLocal` PASS; the other two either SKIP (no creds) or PASS (creds present).

- [ ] **Step 3: Commit**

```bash
git add Tests/CheTransportMCPTests/RailIntegrationTests.swift
git commit -m "test(rail): integration tests with XCTSkip when no credentials"
```

---

## Task 16: CLAUDE.md with NSQL reference

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write CLAUDE.md**

```markdown
# CLAUDE.md — che-transport-mcp

This file is read by LLM agents (Claude Code, Codex, etc.) that use this MCP server. Follow these conventions to avoid common pitfalls.

## What this MCP does

Provides 23 tools over the [TDX 運輸資料流通服務](https://tdx.transportdata.tw/) covering 7 transport modes in Taiwan: Rail (TRA / THSR / 各捷運與輕軌), Bus, Bike (YouBike), Air, Maritime, Traffic, Parking.

This Plan 1 build covers **Rail only** (5 tools). Other modes ship in Plans 2-4.

## Interaction discipline — NSQL

Reference: <https://github.com/kiki830621/NSQL>

This MCP is read-only (no execution risk), but **input ambiguity is frequent**. Examples:

- 「中山」站 → 紅線？淡水線？桃捷？台中？
- 「下一班」→ 時間錨點為何？
- 「往台北」→ 起站為何？

Before calling any tool, **follow NSQL confirmation protocol**:

1. Parse user query into `function + arguments`
2. Render parsed form back to user
3. Wait for confirmation
4. Then call the tool

### Example dialogue

> User: 「下一班高鐵」
>
> Claude: 「我理解你要查 (起站) → (迄站) 從 (現在時間) 起的下一班高鐵。請問起迄站？」
>
> User: 「台北到左營」
>
> Claude: 「即將呼叫 `rail_find_trains(from='1000', to='1070', system='THSR', date='2026-05-20')`。確認嗎？」
>
> User: 對 → Claude 呼叫 tool

### Common ambiguity hotspots

| Query phrase | Ambiguity | Resolution |
|--------------|-----------|------------|
| 「中山」「忠孝」站 | 多 system 同名 | 先 `rail_search_stations(query)`，回多筆讓 user 選 |
| 「下一班」「最近」 | 時間錨點 | Default = now (Asia/Taipei)；若 user 指其他時間需明說 |
| 「往北」「往南」 | 方向 vs 起迄站 | TDX 用 O/D 而非方向；必須轉成兩個 station_id |
| 「自強號」「對號」 | 車種篩選 | TDX 回應已含車種；client 端在 result 內 filter |

## Setup

```bash
make setup-tdx   # one-time, interactive
```

This script prompts for TDX `client_id` / `client_secret`（at <https://tdx.transportdata.tw/register>）and stores them in macOS keychain under service `che-transport-tdx`.

## Tools (Plan 1 — Rail)

- `rail_list_systems()` — 列出 8 個支援 system
- `rail_search_stations(query, system?)` — 模糊搜尋站點 → station_id
- `rail_find_trains(from, to, date, system)` — O/D 找班次
- `rail_status_train(train_no, system)` — 特定列車即時誤點
- `rail_status_station(station_id, system)` — 站到站板（即時）

See `docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md` for full design.

## Architecture invariants

- **Time zone**: All time strings emitted by tools are in Asia/Taipei (`+08:00`)
- **Empty ≠ error**: Tools return `{ "matches": [] }` or `{ "trains": [] }` when no data found. Errors are reserved for system-level issues (auth, network, rate limit)
- **Cache TTL**: 24h static / 1h timetable / 0s live
- **Rate limit**: TDX free tier = 50/min. 429 triggers single retry; second 429 returns error

## Development

```bash
swift build              # build
swift test               # all tests (integration skips if no keychain)
make check-auth          # verify TDX creds work
swift run CheTransportMCP --version
```
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md with NSQL interaction discipline"
```

---

## Task 17: README files

**Files:**
- Create: `README.md`
- Create: `README_zh-TW.md`

- [ ] **Step 1: Write README.md**

```markdown
# che-transport-mcp

A Model Context Protocol server providing real-time Taiwan transport queries via [TDX](https://tdx.transportdata.tw/).

[繁體中文 README](README_zh-TW.md) · [Design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md)

## Status

**v0.1.0** — Rail tools only (TRA / THSR / 4 metros / 2 light rails)

Roadmap:
- v0.1: Rail (this release) ✅
- v0.2: Bus + Bike
- v0.3: Air + Maritime
- v0.4: Traffic + Parking
- v1.0: Release pipeline + marketplace

## Quick start

```bash
git clone <repo>
cd che-transport-mcp
make build
make setup-tdx   # interactive, prompts for TDX credentials
```

Register a free TDX account first at <https://tdx.transportdata.tw/register>.

## Tools (Plan 1)

| Tool | Purpose |
|------|---------|
| `rail_list_systems` | List 8 supported rail systems |
| `rail_search_stations` | Fuzzy search station by name |
| `rail_find_trains` | Find trains by O/D + date |
| `rail_status_train` | Live train status (delay, position) |
| `rail_status_station` | Live station board |

## Architecture

See [design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md).

## License

MIT. See [LICENSE](LICENSE).
```

- [ ] **Step 2: Write Chinese README**

```markdown
# che-transport-mcp

提供臺灣即時交通查詢的 MCP server，資料來源為 [TDX 運輸資料流通服務](https://tdx.transportdata.tw/)。

[English README](README.md)

## 狀態

**v0.1.0** — 僅 Rail 工具（台鐵 / 高鐵 / 4 個捷運 / 2 個輕軌）

Roadmap:
- v0.1: Rail（本版本）✅
- v0.2: 公車 + YouBike
- v0.3: 航班 + 渡輪
- v0.4: 路況 + 停車場
- v1.0: Release pipeline + marketplace 上架

## 快速開始

```bash
git clone <repo>
cd che-transport-mcp
make build
make setup-tdx   # 互動式收 TDX 憑證
```

TDX 帳號免費註冊：<https://tdx.transportdata.tw/register>

## Tools（Plan 1）

| Tool | 用途 |
|------|------|
| `rail_list_systems` | 列出 8 個支援 rail system |
| `rail_search_stations` | 站名模糊搜尋 |
| `rail_find_trains` | O/D + 日期找班次 |
| `rail_status_train` | 特定列車即時誤點 |
| `rail_status_station` | 站到站板（即時）|

## 架構

詳見 [design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md)。

## License

MIT。詳見 [LICENSE](LICENSE)。
```

- [ ] **Step 3: Commit**

```bash
git add README.md README_zh-TW.md
git commit -m "docs: README in English + 繁體中文"
```

---

## Task 18: End-to-end smoke test + tag v0.1.0

**Files:**
- None new; verification step

- [ ] **Step 1: Run full test suite**

```bash
swift test
```

Expected: all unit tests PASS; integration tests SKIP (no creds in CI) or PASS (local).

- [ ] **Step 2: Build release binary**

```bash
swift build -c release
```

Expected: builds without warnings.

- [ ] **Step 3: Verify --version**

```bash
./.build/release/CheTransportMCP --version
```

Expected: `CheTransportMCP 0.1.0`

- [ ] **Step 4: Verify --check-auth (skips gracefully if no creds)**

```bash
./.build/release/CheTransportMCP --check-auth || true
```

If credentials are set, this should print `✓ TDX credentials valid`. If not, error message points to `make setup-tdx`.

- [ ] **Step 5: Verify --help**

```bash
./.build/release/CheTransportMCP --help
```

Expected: prints help message.

- [ ] **Step 6: Tag**

```bash
git tag -a v0.1.0 -m "v0.1.0: Plan 1 — Infrastructure + Rail tools"
```

- [ ] **Step 7: Print summary**

```bash
git log --oneline v0.1.0
```

Confirm all 18 tasks landed as commits.

---

## Self-Review Notes

After plan execution, verify:

1. **Spec coverage**:
   - ✅ Section 1 (Project structure): Tasks 1-2
   - ✅ Section 2 (Auth): Tasks 4, 8
   - ✅ Section 3 (Tool catalog Rail): Tasks 10-14
   - ✅ Section 4 (Cache): Task 3
   - ✅ Section 5 (Error handling): Tasks 5-6
   - ✅ Section 6 (Testing): Tasks 9-15
   - ✅ Section 7 (NSQL discipline): Task 16
   - ⏳ Sections 8-10: deferred to Plans 2-5
2. **23 tool target**: 5/23 in this plan; rest in Plans 2-5
3. **MCP SDK API verification**: Task 10 step 3 has a NOTE — verify `Tool` / `registerTool` API matches actual MCP swift-sdk 0.12 by referencing `che-ical-mcp/Sources/CheICalMCP/Server.swift` before implementing
4. **No placeholders**: All code shown is concrete; only TDX endpoint paths are taken from TDX docs and should be cross-checked at <https://tdx.transportdata.tw/api-service/swagger>

---

## Next plans

- **Plan 2**: Bus (5 tools) + Bike (3 tools)
- **Plan 3**: Air (3 tools) + Maritime (2 tools)
- **Plan 4**: Traffic (3 tools) + Parking (2 tools)
- **Plan 5**: Release pipeline (mcpb, Developer ID sign, notarize, marketplace publish)
