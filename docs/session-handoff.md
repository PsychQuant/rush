# Session Handoff — for the next Claude Code session

When you (Claude, in a future session) start working in this folder, read this first. It will orient you to project state + the cleanest place to start.

## TL;DR

- **Project**: `che-transport-mcp` — Swift MCP server exposing Taiwan transport data (TDX API) as 23 LLM tools across 7 modes
- **Current state**: **v0.1.0 shipped**. Infrastructure + 5 Rail tools. 16 unit tests passing.
- **What's next**: 4 small cleanups (`docs/v0.2-backlog.md` Section A) → Plan 2 (Bus + Bike tools, Section B)

## Project layout

```
che-transport-mcp/
├── README.md / README_zh-TW.md  # User-facing entry
├── CLAUDE.md                    # ★ Agent interaction rules — read first
├── CHANGELOG.md                 # Release history (Keep a Changelog format)
├── LICENSE                      # MIT
├── Package.swift                # Swift PM, MCP swift-sdk 0.12+
├── Makefile                     # build / test / setup-tdx / check-auth / clean
├── scripts/setup-tdx.sh         # Interactive credential setup
├── Sources/CheTransportMCP/
│   ├── main.swift               # CLI flags (--version / --help / --check-auth)
│   ├── Server.swift             # MCP server bootstrap
│   ├── Version.swift            # 0.1.0
│   ├── Auth.swift               # Keychain wrapper
│   ├── Cache.swift              # Actor-based TTL cache
│   ├── TDXClient.swift          # OAuth2 + HTTP + 429 retry
│   ├── Models/RailModels.swift  # Codable structs + RailSystem enum
│   └── Tools/RailTools.swift    # 5 Rail tools, defineTools() + handleCall switch
├── Tests/CheTransportMCPTests/
│   ├── AuthTests.swift
│   ├── CacheTests.swift
│   ├── TDXClientTests.swift
│   ├── RailModelsTests.swift
│   ├── RailToolsTests.swift
│   ├── RailIntegrationTests.swift  # XCTSkip when no TDX creds
│   ├── SmokeTest.swift
│   └── Fixtures/                   # JSON test fixtures
└── docs/
    ├── superpowers/specs/2026-05-20-che-transport-mcp-design.md
    ├── superpowers/plans/2026-05-20-plan-1-infrastructure-and-rail.md
    ├── v0.2-backlog.md         # ★ Next session pickup list — read for what to do
    ├── related-issues.md       # External refs (IDD#111, NSQL, TDX, etc.)
    └── session-handoff.md      # This file
```

## Key conventions established in v0.1.0

These are load-bearing. Don't break them without thinking through impact.

### 1. MCP tool registration pattern

There is **ONE** `Server.withMethodHandler(ListTools.self)` and **ONE** `Server.withMethodHandler(CallTool.self)` per Server instance. Adding a new tool means:

1. Append a `Tool(name:description:inputSchema:annotations:)` to whatever the tool module's `defineTools()` returns
2. Add a `case "tool_name":` to the switch in `handleCall`
3. Add a private `executeToolName(arguments:client:cache:)` async function

**Anti-pattern**: do NOT call `withMethodHandler(ListTools.self)` multiple times — the second call overwrites the first. This is why Plan 2 needs a `ToolRegistry` refactor before adding Bus/Bike modules (see `docs/v0.2-backlog.md` Section B).

### 2. Three-tier cache TTL

| Data type | TTL | Examples |
|-----------|-----|----------|
| Static (stations, routes, system metadata) | 86400 (24h) | `*/Station` endpoints |
| Daily-changing (timetables, fares) | 3600 (1h) | `DailyTrainTimetable/OD/...` |
| Live (delays, arrivals, positions, parking spaces) | 0 (do not cache) | `TrainLiveBoard/...`, `StationLiveBoard/...` |

The `Cache.set(ttl: 0)` guard means TTL 0 is a no-op (correct — live data must not be cached).

### 3. Empty ≠ error

Tools return `{"matches": [], "trains": [], ...}` when no data matches — that's a valid result, not an error. Errors (`isError: true` in MCP) are reserved for system-level issues: auth failure, network unreachable, rate limit exhausted, schema drift.

### 4. 臺/台 bidirectional normalization

Both the query AND the candidate station name are normalized to use `臺` before comparison. Don't normalize only one side.

### 5. NSQL interaction discipline

`CLAUDE.md` mandates: before any tool call, parse the user query into `function + arguments`, render the parsed form back, wait for confirmation. Especially important for the ambiguity hotspots documented in `CLAUDE.md`.

## How to start work

### If you want to use v0.1.0 (try the tools)

```bash
cd /Users/che/Developer/che-mcps/che-transport-mcp
make build
make setup-tdx   # one-time, prompts for TDX credentials
# Then add to Claude Code MCP config (~/.config/claude/mcpServers or similar)
```

### If you want to continue development

```bash
cd /Users/che/Developer/che-mcps/che-transport-mcp
swift test   # confirm 16 pass / 2 skip baseline still holds

# Then pick a backlog item:
# - 4 minor cleanups: `docs/v0.2-backlog.md` Section A
# - Plan 2 (Bus + Bike): `docs/v0.2-backlog.md` Section B
# - Plan 3-4 (other modes): Section C
# - Plan 5 (release pipeline): Section D
```

## Things you (Claude) might want to verify before starting

1. **Tests still pass** — `swift test` should show 15 unit + 1 integration local PASS, 2 integration SKIP (no creds). If anything fails, something drifted since v0.1.0.
2. **Build clean** — `swift build` should complete without warnings.
3. **Tag intact** — `git tag --list` should show `v0.1.0`.
4. **No uncommitted work** — `git status` should be clean.
5. **MCP swift-sdk version** — `Package.swift` declares `.upToNextMinor(from: "0.12.0")`. If a newer minor version (0.13.x+) has shipped, the API may have changed.

## What NOT to do

- Don't refactor working code unless a specific backlog item asks for it. v0.1.0 took 18 carefully-reviewed tasks to land cleanly — speculative cleanups risk breaking what works.
- Don't add tools beyond the 23 catalogued in the design spec without first updating the spec and (probably) opening a new Plan.
- Don't change cache TTLs without a TDX-side reason. The 24h/1h/0s tiers were chosen deliberately.
- Don't add `disabled_*` flags or feature toggles. YAGNI per `CLAUDE.md` guidelines.

## Final review findings (recap)

The v0.1.0 final review found **0 blocking issues**. All 6 minor issues are documented in `docs/v0.2-backlog.md` Section A + E. If the user asks you to "fix the v0.1 issues", that's the list.

## Last words

This was built across two long sessions on 2026-05-19 → 2026-05-20 via subagent-driven-development from a superpowers brainstorming → writing-plans flow. The complete history is in `git log` and in the spec/plan under `docs/superpowers/`. If something here is confusing, trace it back through those artifacts before assuming the design is wrong — it might just be context you don't have yet.
