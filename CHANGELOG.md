# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] — 2026-06-01

### Added
- `rail_route(from, to, depart_after?, system)` — TRA **time-dependent** O/D routing (#7, Stage 1 of the time-dependent transit-routing engine). Routes over the real `DailyTrainTimetable` (per-train departure/arrival times) with a connection-scan earliest-arrival search, then applies live `TrainLiveBoard` delays so the chosen itinerary reflects current conditions — a delayed train can lose to a later on-time one. Returns `legs[]` (train_no, from/to, dep/arr times, delay_min, `source: live|scheduled`) + `arrival_time` + `duration_min`. TRA-only (the only mode with both a public timetable and a live delay board); distinct from `rail_find_trains` (which lists all trains). Tool count 22 → 23. Reuses existing `RailODFare`/`RailStopTime`/`RailLiveTrain` models + existing registry endpoints (both v3-wrapped, decoded via `TDXDecode.list`); graceful when the timetable or live board is unavailable (empty + note ≠ error).


### Added
- `metro_find_route` now does **cross-line transfer** routing (#6), not just direct. The metro network is modelled as a graph (stations as nodes; same-line adjacency from `S2STravelTime`; transfer edges from a new `LineTransfer` dataset weighted by walk time + estimated boarding wait) and the shortest path is returned. A direct route is simply a zero-transfer path, so the same query also catches cases where a 環狀線 transfer beats a long direct ride.
- New `metroLineTransfer` registry endpoint + `MetroLineTransfer` model + contract case (contract cases 30 → 31). Single-line systems (HTTP 400 / empty) degrade gracefully to no transfer edges.

### Changed
- **`metro_find_route` output shape** evolved from the v0.4.0 flat single-line shape to `routes[]`, each with `legs[]` (one leg per line ridden — line name/colour, per-leg travel time, headway), `transfers[]` (one per line change — interchange station, from/to line, `walk_min`, estimated `wait_min`), `transfer_count`, and total `travel_time_min`. Tool count unchanged (22 — extends the existing tool). The #5 direct short-circuit gate is replaced by always building the graph.

## [0.4.0] — 2026-05-31

### Added
- `metro_find_route(from, to, system)` — direct (single-line) metro O/D routing across the 6 metro systems (TRTC/TYMC/KRTC/TMRT/NTDLRT/KLRT). Returns the connecting line (name + colour), station-to-station travel time, and current-period service headway — metros run on headways, not fixed timetables, so it does not return a specific departure time. No direct line → empty `routes` + transfer hint (transfer routing tracked in #6). Tool count: 21 → 22. (#5)
- 4 metro routing endpoints (`StationOfRoute` / `S2STravelTime` / `Frequency` / `Line`) added to the `TDXEndpoints` registry + live contract enumeration (contract cases 26 → 30). Production resolves all paths through the registry; no inline metro path literals.

### Notes
- Travel-time accumulation is direction-agnostic: TDX `S2STravelTime` stores segments in a single direction only (e.g. 板南線 stores the descending order), and adjacent-station run-time is symmetric, so both orders are matched. Headway is selected by Asia/Taipei weekday + time-of-day band (national-holiday detection is out of scope for v1).

## [0.3.0] — 2026-05-30

### Added
- `TDXEndpoints` — single source of truth for every TDX API path; production tools resolve paths through it (no inline path literals).
- Registry-driven live contract tests (`ContractTests`) — one assertion per non-static endpoint (not-404 → 200 → decode), opt-in via `TDX_CONTRACT`, skipped without credentials. New `contract-tests.yml` runs them nightly / on release / on dispatch (never on PRs).
- `TDXDecode.list` — tolerates both bare-array and wrapped-object (`{…,"<Dataset>":[…]}`) TDX responses.

### Fixed
- Rail endpoint path drift (#4): THSR is `v2` not `v3`; THSR timetable is `DailyTimetable`; metro station is `v2/Rail/Metro/Station/{op}`; traffic news is `Live/News/Freeway`.
- Wrapped-response silent-empty bugs in traffic (×3) and parking (×2) — production decoded `[]` because TDX wraps the array.
- `FlightInfo.DepartureRemark`/`ArrivalRemark` decoded as `String` (was `LocalizedName`) — `air_find_flights` was returning empty.
- `rail_status_train` uses the v3 `TrainLiveBoard` collection + `$filter` (the `/Train/{no}` path-param form 404s).

### Removed
- **Maritime tools** (`maritime_list_routes`, `maritime_status_schedule`). TDX serves no maritime endpoint on its unified API (every `v2`/`v3` `Maritime`/`Ship` path 404s) and the legacy PTX `Ship` API is decommissioned (403 regardless of auth). Tool count: 23 → 21, modes: 7 → 6. See #4.

## [0.2.3] — 2026-05-29

### Fixed

- Tool JSON output no longer leaks IEEE-754 float noise. Coordinates like `25.04` previously rendered as `25.039999999999999` because `JSONSerialization` formats every `Double` with up to 17 significant digits — and rounding the value cannot fix this (`25.04` has no exact IEEE-754 representation, so the rounded result is the same bit pattern). New `JSONSanitize.clean` recursively rewrites every `Double` to its shortest round-trippable form via `NSDecimalNumber(Double.description)`, wired into all 8 tool-output serialization sites (6 `jsonResult` helpers + 2 inline `RailTools` sites). Value-preserving (exact numeric round-trip), `Int`/`Bool` untouched, non-finite values and raw TDX passthroughs unaffected. (#1, PR #2)

## [0.2.2] — 2026-05-23

### Changed

- `--setup` now delegates to [`che-keychain`](https://github.com/PsychQuant/che-keychain) if installed in `~/bin/`, `/usr/local/bin/`, `/opt/homebrew/bin/`, or `$PATH`. Soft dependency — when `che-keychain` is available, the user sees a **native macOS dialog** (NSAlert + NSStackView with NSTextField + NSSecureTextField) for both fields in one popup, no Terminal getpass prompt. The dialog runs inside the signed `che-keychain` binary so the typed `client_secret` never enters this process either. When `che-keychain` is not found, the existing in-process getpass flow runs unchanged — no behavior regression.
- Setup banner under the getpass fallback now points users at the `che-keychain` install URL for the nicer UX.
- Updated TDX portal navigation hint: `會員中心 → 資料服務 → API 金鑰 → 編輯` (the previous wording skipped the `資料服務` submenu and the `編輯` reveal step, which is exactly where new users get stuck).

## [0.2.1] — 2026-05-22

### Added

- `CheTransportMCP --setup` — interactive TDX credential setup built into the binary. Prompts for `client_id` (visible) and `client_secret` (hidden, via `getpass`), writes both to keychain via `Auth.save`, then verifies with a real OAuth round-trip. Replaces the repo-coupled `scripts/setup-tdx.sh` as the canonical setup path: single signed+notarized artifact, shared keychain code with `Auth.read` (no read/write drift), unit-testable validation. `Setup.swift` + 6 `SetupTests`.

### Changed

- `--help` text + `AuthError.itemNotFound` message now point at `CheTransportMCP --setup` instead of `make setup-tdx` (the latter only works inside a cloned source repo; the binary is what plugin users actually have)

## [0.2.0] — 2026-05-21

23 tools across all 7 transport modes (Rail / Bus / Bike / Air / Maritime / Traffic / Parking). Architecture refactored around a `ToolRegistry` actor so mode modules can coexist. Released to `PsychQuant/che-transport-mcp`.

### Added

#### ToolRegistry (architecture)

- New `ToolRegistry` actor aggregates `[Tool]` + per-name dispatchers across mode modules. MCP swift-sdk only allows one `withMethodHandler(ListTools.self)` / `withMethodHandler(CallTool.self)` per Server — the registry lets each mode `register(into:)` append without overwriting. Server.swift now installs the two MCP handlers exactly once.

#### Bus tools (5) — city-scoped, 22 BusCity codes

- `bus_search_routes` / `bus_search_stops` — fuzzy match with 臺/台 normalization
- `bus_find_routes` — O/D intersection via `/v2/Bus/StopOfRoute/City/{City}`
- `bus_status_arrivals` — ETA at stop via EstimatedTimeOfArrival + `$filter`
- `bus_status_positions` — live positions via RealTimeNearStop
- City required (not optional): 22 parallel fan-out would exceed TDX 50/min, and "中山路" exists in many cities — disambiguation needed

#### Bike tools (3) — YouBike 1.0 + 2.0

- `bike_search_stations` — name search + optional `service_type` filter
- `bike_stations_nearby` — haversine distance sort + live availability join, radius clamped to [50, 3000] m
- `bike_status_station` — single-station live rent/return count

#### Air tools (3) — IATA-coded

- `air_list_airports` — Taiwan airport master
- `air_find_flights` — schedule lookup by airport + Arrival/Departure (10-min cache)
- `air_status_flights` — live FIDS board (no cache)
- IATA 3-letter validation with case-insensitive uppercase normalization

#### Maritime tools (2) — operator-scoped

- `maritime_list_routes` — route master, optional operator_id filter
- `maritime_status_schedule` — raw TDX JSON pass-through wrapped in `{route_id, raw}` envelope (per-operator schema varies)

#### Traffic tools (3)

- `traffic_freeway_live` — section-level speed / travel time / congestion (no cache)
- `traffic_incidents` — 5-min cached news feed with client-side keyword filter
- `traffic_cctv` — 24h cached CCTV inventory with stream URLs

#### Parking tools (2) — 22 ParkingCity codes

- `parking_list_lots` — off-street car park master with keyword filter
- `parking_status` — live available-spaces lookup with optional lot_id filter

### Changed

- `rail_search_stations` 在未指定 `system` 時改用 `withThrowingTaskGroup` 平行抓取 8 個 system 的 station 列表，cold cache 首次呼叫延遲大幅下降；TaskGroup yield order 非確定，故額外按 `RailSystem.allCases` 重排以保持輸出穩定（backlog A3）
- `Cache` actor 引入預設 1000 筆的 LRU 上限（`maxEntries` 可注入），含 keyOrder bookkeeping 與 TTL 過期同步清理，避免長時 session 記憶體無界成長；行為向後相容（既有 3 個 cache test 不需改動）（backlog A4）
- `RailTools.register` 改 signature 從 `(server:, client:, cache:)` 改為 `(into:, client:, cache:)` — 接 ToolRegistry 而非直接 install MCP handlers。`Server.swift` 統一 install 一次

### Fixed

- `TDXError.rateLimited` 錯誤訊息誤導：原本說「retry in 60s」但實際只 retry 一次（1s sleep）。改為描述真實行為與 TDX per-minute window（backlog A1）
- `rail_status_station` 的 `window_min` 在 schema 接受但 TDX endpoint 自帶預設視窗、client 並未過濾 — 在 `CLAUDE.md` 工具清單下加 forward-compatibility 註記（backlog A2）

### Testing

- Total test count rose from 18 → 52 (+34): ToolRegistry (3), Bus (7), Bike (7), Air (4), Maritime (2), Traffic (3), Parking (4), Cache LRU (4)
- All 50 unit tests pass; 2 integration tests still XCTSkip without TDX credentials

## [0.1.0] — 2026-05-20

First public-ready cut. Infrastructure + 5 Rail tools shipped.

### Added

#### Infrastructure

- Swift Package Manager project skeleton with MCP swift-sdk 0.12+ dependency
- `Cache.swift` — actor-based in-memory TTL cache (24h / 1h / 0s tiers)
- `Auth.swift` — macOS Keychain-backed credential storage under service `che-transport-tdx`
- `TDXClient.swift` — TDX OAuth2 client credentials flow, in-memory token cache (60s early refresh), HTTP fetch with bearer auth, 429 single-retry with 1s sleep, 401 token invalidation, percent-encoded form bodies, guarded URL construction
- `Server.swift` — MCP stdio server with unified `ListTools` / `CallTool` dispatch
- `main.swift` — CLI entrypoint with `--version` / `--help` / `--check-auth` flags
- `scripts/setup-tdx.sh` — interactive credential bootstrap via `security` CLI
- `Makefile` — `build` / `test` / `setup-tdx` / `check-auth` / `clean` targets

#### Rail tools (5)

- `rail_list_systems()` — list 8 supported rail systems (TRA / THSR / TRTC / TYMC / KRTC / TMRT / NTDLRT / KLRT)
- `rail_search_stations(query, system?)` — fuzzy station name search with 臺/台 bidirectional normalization, returns matches across all systems by default
- `rail_find_trains(from, to, date, system)` — O/D timetable lookup with strict YYYY-MM-DD validation (round-trip check + `en_US_POSIX` locale), TRA/THSR only
- `rail_status_train(train_no, system)` — live train delay/position via `TrainLiveBoard/Train`, TRA/THSR only
- `rail_status_station(station_id, system, window_min?)` — live station board via `StationLiveBoard/Station`, TRA/THSR only

#### Models

- `RailModels.swift` — Codable structs for TDX schema (LocalizedName, RailPosition, RailStation, RailTrainInfo, RailStopTime, RailODFare, RailLiveTrain) plus `RailSystem` enum with `displayName` and `apiPath` properties

#### Testing

- Unit tests: AuthTests (2), CacheTests (3), TDXClientTests (2), RailModelsTests (2), RailToolsTests (5), SmokeTest (1) — 15 total, all passing
- Integration tests: `RailIntegrationTests` (3 tests, 2 of which `XCTSkip` gracefully when no TDX credentials in keychain)
- JSON fixtures in `Tests/CheTransportMCPTests/Fixtures/` (oauth_response, rail_station, rail_timetable)

#### Documentation

- `CLAUDE.md` — agent interaction discipline with [NSQL](https://github.com/kiki830621/NSQL) confirmation protocol reference, ambiguity hotspots table (中山/下一班/方向/車種)
- `README.md` + `README_zh-TW.md` — bilingual project entry, tool catalog, roadmap
- `docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md` — full design spec (architecture, tool catalog, cache/error/testing strategy)
- `docs/superpowers/plans/2026-05-20-plan-1-infrastructure-and-rail.md` — 18-task implementation plan (executed via subagent-driven-development)

### Architecture decisions

- **Smart wrapper over thin pass-through** — tools combine multiple TDX endpoints when needed, normalize fields, provide concept-level operations
- **Unified MCP dispatch** — single `withMethodHandler(ListTools.self)` + single `withMethodHandler(CallTool.self)` with switch-by-name (matches MCP swift-sdk 0.12 actual API; the plan's per-tool `registerTool` pseudocode was adjusted at T10)
- **3-tier cache TTL** — 24h static (stations/routes), 1h timetable, 0s live
- **Empty ≠ error** — empty result sets return normally; only system-level failures (auth, network, rate limit, schema drift) return `isError: true`
- **臺/台 bidirectional normalization** — both query and station name pass through the same normalization before comparison

### Known limitations (deferred to v0.2)

- `TDXError.rateLimited` error message says "retry in 60s" but actual single-retry sleeps 1s only (cosmetic mismatch)
- `rail_status_station` accepts `window_min` parameter but TDX endpoint uses its own default window — accepted-but-ignored, not documented in CLAUDE.md
- `rail_search_stations` with no `system` filter fires 8 sequential HTTP requests on cold cache (24h cache means steady-state cost is negligible, but cold start can take seconds)
- `Cache` is unbounded — fine for rail (~500 KB), needs size cap before bus stops land in v0.2

[Unreleased]: https://github.com/PsychQuant/che-transport-mcp/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/PsychQuant/che-transport-mcp/releases/tag/v0.2.2
[0.2.1]: https://github.com/PsychQuant/che-transport-mcp/releases/tag/v0.2.1
[0.2.0]: https://github.com/PsychQuant/che-transport-mcp/releases/tag/v0.2.0
[0.1.0]: https://github.com/kiki830621/che-mcps/releases/tag/v0.1.0
