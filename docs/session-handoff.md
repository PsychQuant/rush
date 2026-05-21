# Session Handoff — for the next Claude Code session

When you (Claude, in a future session) start working in this folder, read this first. It will orient you to project state + the cleanest place to start.

## TL;DR

- **Project**: `che-transport-mcp` — Swift MCP server exposing Taiwan transport data (TDX API) as 23 LLM tools across 7 modes
- **Current state**: **all 23 tools landed, source on v0.2.0 awaiting tag + release-signed**. 52 unit tests passing.
- **What's next**: maintainer decides whether to (a) cut v0.2.0 release (tag + notarize + publish .mcpb), or (b) pick from Section E nice-to-haves, or (c) start v0.3 work

## Project layout (snapshot at v0.2.0-dev)

```
che-transport-mcp/
├── README.md / README_zh-TW.md  # User-facing entry — 23-tool catalogue
├── CLAUDE.md                    # ★ Agent interaction rules + tool listings — read first
├── CHANGELOG.md                 # Keep a Changelog; Unreleased section holds v0.2 work
├── LICENSE                      # MIT
├── Package.swift                # Swift PM, MCP swift-sdk 0.12+
├── Makefile                     # build / test / setup-tdx / check-auth / clean
│                                # release / release-signed / verify-release-ready / install
├── scripts/
│   ├── setup-tdx.sh             # Interactive credential setup
│   └── build-mcpb.sh            # Build + sign + (optionally) notarize + pack .mcpb
├── mcpb/
│   ├── manifest.json            # Claude Desktop bundle manifest (all 23 tools)
│   └── server/                  # built-artefacts dir (gitignored)
├── Sources/CheTransportMCP/
│   ├── main.swift               # CLI flags (--version / --help / --check-auth)
│   ├── Server.swift             # Wires all 7 mode modules into ToolRegistry
│   ├── Version.swift            # 0.2.0
│   ├── Auth.swift               # Keychain wrapper
│   ├── Cache.swift              # Actor-based TTL cache with 1000-entry LRU cap
│   ├── TDXClient.swift          # OAuth2 + HTTP + 429 retry
│   ├── ToolRegistry.swift       # Aggregates [Tool] + dispatcher across modes
│   ├── Models/                  # RailModels / BusModels / BikeModels / AirModels /
│   │                            #   MaritimeModels / TrafficModels / ParkingModels
│   └── Tools/                   # RailTools / BusTools / BikeTools / AirTools /
│                                #   MaritimeTools / TrafficTools / ParkingTools
├── Tests/CheTransportMCPTests/
│   ├── AuthTests.swift
│   ├── CacheTests.swift                   # Includes LRU eviction tests (+4 from v0.1)
│   ├── TDXClientTests.swift
│   ├── ToolRegistryTests.swift            # NEW
│   ├── RailModelsTests.swift
│   ├── RailToolsTests.swift
│   ├── BusToolsTests.swift                # NEW
│   ├── BikeToolsTests.swift               # NEW
│   ├── AirToolsTests.swift                # NEW
│   ├── MaritimeToolsTests.swift           # NEW
│   ├── TrafficToolsTests.swift            # NEW
│   ├── ParkingToolsTests.swift            # NEW
│   ├── RailIntegrationTests.swift         # XCTSkip when no TDX creds
│   ├── SmokeTest.swift
│   └── Fixtures/
└── docs/
    ├── superpowers/specs/2026-05-20-che-transport-mcp-design.md
    ├── superpowers/plans/2026-05-20-plan-1-infrastructure-and-rail.md
    ├── v0.2-backlog.md         # Sections A–D done; Section E (nice-to-haves) remains
    ├── related-issues.md
    └── session-handoff.md      # This file
```

## Key conventions (still load-bearing in v0.2)

### 1. Single MCP handler installation, registry-driven

`Server.swift` installs `withMethodHandler(ListTools.self)` and `withMethodHandler(CallTool.self)` exactly once. Each mode module appends into `ToolRegistry` via `register(into:)`. Adding a new mode:

1. Add `Sources/CheTransportMCP/Models/<Mode>Models.swift` (Codable structs + any enum)
2. Add `Sources/CheTransportMCP/Tools/<Mode>Tools.swift` with `defineTools()` + `register(into:)` + `handleCall(name:arguments:client:cache:)`
3. Append one line in `Server.swift`: `await <Mode>Tools.register(into: registry, client: client, cache: cache)`

### 2. Three-tier cache TTL (+ live)

| Data type | TTL | Examples |
|-----------|-----|----------|
| Static (stations, routes, lots, CCTV) | 86400 (24h) | `*/Station`, `*/Route`, `*/CarPark`, `*/CCTV` |
| Daily-changing (timetables, schedules) | 3600 (1h) | `DailyTrainTimetable/OD/...`, `Maritime/Schedule` |
| News / short fuse | 300-600 (5-10 min) | `Road/Traffic/News`, `Air/FIDS` non-live |
| Live (delays, arrivals, positions, parking spaces, FIDS live) | 0 (do not cache) | `*LiveBoard/...`, `EstimatedTimeOfArrival/...`, `RealTimeNearStop/...` |

### 3. Empty ≠ error

All 23 tools return `{ "matches": [], "trains": [], ... }` when no data matches. Errors (MCP `isError: true`) are reserved for system-level issues: auth failure, network unreachable, rate limit exhausted, schema drift.

### 4. 臺/台 bidirectional normalization

Both query and candidate name are normalized before comparison. Don't normalize one side only.

### 5. NSQL interaction discipline

`CLAUDE.md` mandates: before any tool call, parse user query into `function + arguments`, render the parsed form back, wait for confirmation. Especially important for ambiguity hotspots (which city / which system / what time anchor).

### 6. LRU cache cap

`Cache(maxEntries: N)` defaults to 1000 entries; keyOrder bookkeeping evicts least-recently-used on overflow.

### 7. City-scoped tools require `city` (no fan-out)

Bus and Parking tools require `city` because 22-way parallel fan-out would exceed TDX 50/min, and ambiguity ("中山路" exists in many cities) wouldn't resolve without it.

## How to cut a release

**v0.2.0 已發 (2026-05-21)** — see [release](https://github.com/PsychQuant/che-transport-mcp/releases/tag/v0.2.0) and the matching plugin entry at [psychquant-claude-plugins](https://github.com/PsychQuant/psychquant-claude-plugins/tree/main/plugins/che-transport-mcp). The flow below is the template for v0.3.0+.

### Step 1: Source-repo release

```bash
# Pre-flight
make verify-release-ready   # warns about drift between Version.swift and latest tag
swift test                  # confirm all unit + integration baseline still green

# CHANGELOG: move Unreleased → [X.Y.Z] dated today, leave Unreleased empty
# Bump Sources/CheTransportMCP/Version.swift + mcpb/manifest.json to X.Y.Z

git add CHANGELOG.md Sources/CheTransportMCP/Version.swift mcpb/manifest.json
git commit -m "release: prepare vX.Y.Z cut"
git push origin main

# Tag
git tag vX.Y.Z && git push origin vX.Y.Z

# Build signed + notarized
export DEVELOPER_ID="F2523DCF6D02BE99B67C7D27F633119292DA4934"
export NOTARY_PROFILE="che-mcps-notary"
make release-signed  # ~2-10 min; xcrun notarytool submit --wait

# Publish — CRITICAL: include the raw CheTransportMCP binary, not just the .mcpb,
# because the plugin wrapper greps browser_download_url for /CheTransportMCP" .
# Forget this and end users see "no download URL found at PsychQuant/che-transport-mcp".
gh release create vX.Y.Z \
  mcpb/server/CheTransportMCP \
  mcpb/server/CheTransportMCP.sha256 \
  mcpb/che-transport-mcp-X.Y.Z.mcpb \
  mcpb/che-transport-mcp-X.Y.Z.mcpb.sha256 \
  --repo PsychQuant/che-transport-mcp \
  --title "vX.Y.Z — …" \
  --notes-file <(awk '/## \[X.Y.Z\]/,/## \[/' CHANGELOG.md | head -n -1)
```

### Step 2: Plugin-marketplace bump

Bump `plugins/che-transport-mcp/.claude-plugin/plugin.json` + matching entry in `.claude-plugin/marketplace.json` to `X.Y.Z`. Fast path:

```bash
/plugin-tools:plugin-update che-transport-mcp
```

This bumps both files, commits, pushes, runs `claude plugin marketplace update`, and runs `claude plugin update`.

### Step 3: End-user side (automatic)

Wrapper's version-aware auto-download notices the sidecar mismatch on next MCP spawn and pulls the new binary atomically. No user action needed beyond restarting Claude Code (`Cmd+Q` + reopen for MCP servers).

See the plugin's [CLAUDE.md → Full upgrade chain](https://github.com/PsychQuant/psychquant-claude-plugins/blob/main/plugins/che-transport-mcp/CLAUDE.md#full-upgrade-chain-binary--plugin) for the canonical reference.

## Things you might want to verify before starting

1. `swift test` — 50 unit + 1 integration local PASS, 2 integration SKIP without creds
2. `swift build` — no warnings
3. `git tag --list` — should show `v0.1.0` + `v0.2.0` (released 2026-05-21)
4. `git status` — clean
5. `make verify-release-ready` — reports drift state honestly
6. MCP swift-sdk version (`Package.swift` declares `.upToNextMinor(from: "0.12.0")`); 0.13.x+ may have API changes

## What NOT to do

- Don't refactor working code unless a Section E backlog item asks for it
- Don't change cache TTL tiers without TDX-side reason
- Don't add `disabled_*` flags or feature toggles (YAGNI per CLAUDE.md)
- Don't merge the 22-city BusCity / ParkingCity enums without checking that TDX coverage actually overlaps fully — they look identical but the divergence may matter later
- Don't relax City to optional on Bus or Parking tools (the 22-way fan-out would breach rate limit + disambiguation gets harder)

## What's actually left

| Section | Status |
|---------|--------|
| A — v0.1 cleanups (4 items)                                  | ✅ commit 4bba5ac |
| B — Plan 2 (ToolRegistry + Bus + Bike, 8 tools)              | ✅ commit d365b86 |
| C — Plans 3-4 (Air + Maritime + Traffic + Parking, 10 tools) | ✅ commit 2cc2f0b |
| D — Plan 5 (release pipeline scaffold)                       | ✅ commit de5a5c6 (scaffolded; tag + notarization await user) |
| E — Nice-to-haves                                            | Open, no specific plan, low priority |

Section E open items (see `docs/v0.2-backlog.md`):
- Centralised MCP tools/call argument validation
- Telemetry / invocation logging hook
- Schema drift contract testing (manual)
- Per-endpoint rate limit awareness
- Negative test cases for `rail_find_trains` (bad inputs)
- Format-documentation for `rail_status_train` train_no per system

These are non-blocking polish work. Tackle on demand.

## Last words

v0.2 was built across one extended session on 2026-05-20 via the v0.2-backlog → Section A–D loop. Pattern was: per module, write Models + Tools, wire into Server.swift, add tests covering the pure-function parts (enum coverage, fuzzy match, parameter validation, Codable shape). Live integration deferred to a future session that has TDX credentials (`make setup-tdx` then `make check-auth`).

If you confused about why something is the way it is, trace through `git log` — the commit messages explain "why" alongside "what".
