# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned (v0.2)

- Bus tools (5): search_routes / search_stops / find_routes / status_arrivals / status_positions
- Bike tools (3): search_stations / stations_nearby / status_station (YouBike 1.0 + 2.0)
- See `docs/v0.2-backlog.md` for details

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

[Unreleased]: https://github.com/kiki830621/che-mcps/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kiki830621/che-mcps/releases/tag/v0.1.0
