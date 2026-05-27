# che-transport-mcp — CLAUDE.md

Plugin wrapper for the `che-transport-mcp` MCP server (Swift, source at [PsychQuant/che-transport-mcp](https://github.com/PsychQuant/che-transport-mcp)).

## What this plugin does

Provides **23 MCP tools** querying Taiwan transport data via [TDX 運輸資料流通服務](https://tdx.transportdata.tw/) across 7 transport modes. Read-only — no execution risk.

## Tools surface

| Mode | Count | Tools |
|------|-------|-------|
| Rail | 5 | `rail_list_systems`, `rail_search_stations`, `rail_find_trains`, `rail_status_train`, `rail_status_station` |
| Bus | 5 | `bus_search_routes`, `bus_search_stops`, `bus_find_routes`, `bus_status_arrivals`, `bus_status_positions` |
| Bike | 3 | `bike_search_stations`, `bike_stations_nearby`, `bike_status_station` |
| Air | 3 | `air_list_airports`, `air_find_flights`, `air_status_flights` |
| Maritime | 2 | `maritime_list_routes`, `maritime_status_schedule` |
| Traffic | 3 | `traffic_freeway_live`, `traffic_incidents`, `traffic_cctv` |
| Parking | 2 | `parking_list_lots`, `parking_status` |

MCP tool names appear as `mcp__che-transport-mcp__<tool>` or `mcp__plugin_che-transport-mcp_transport__<tool>` depending on Claude Code's registration namespace.

## Skills

| Skill | When to invoke |
|-------|----------------|
| `/che-transport-mcp:setup-tdx` | First-time TDX credential setup, or when SessionStart banner shows "⚠ TDX credentials missing" |
| `/che-transport-mcp:today-rail` | Quick O/D rail timetable lookups (台北→左營, 下一班高鐵, 末班自強號) |
| `/che-transport-mcp:nearby-bike` | YouBike geographic search (附近 YouBike, 哪裡借／還車) |

## NSQL interaction discipline

This MCP is read-only (no execution risk), but **input ambiguity is frequent**:

- 「中山」站 → 紅線？淡水線？桃捷？台中？
- 「下一班」→ 時間錨點為何？
- 「往台北」→ 起站為何？

Before calling any tool, **follow NSQL confirmation protocol**:

1. Parse the user query into `function + arguments`
2. Render the parsed form back to the user
3. Wait for confirmation
4. Then call the tool

### Common ambiguity hotspots

| Query phrase | Ambiguity | Resolution |
|--------------|-----------|------------|
| 「中山」「忠孝」 | Multi-system same-name stations | Call `rail_search_stations(query)` first, show user the matches |
| 「下一班」「最近」 | Time anchor | Default = now (Asia/Taipei) unless user says otherwise |
| 「往北」「往南」 | Direction phrases | Convert to two station_ids; TDX takes O/D, not directions |
| 「自強號」「對號」 | Train type filter | Client-side filter after `rail_find_trains` returns |
| 「中山路 / 中山國中」 in bus context | City scoping | Bus tools require `city` — disambiguate Taipei vs Kaohsiung vs ... |
| 「我附近」 in bike context | Coordinates | Convert landmark to lat/lon via WebSearch; confirm before calling |

## Architecture invariants (binary-side, inherited)

These come from the underlying Swift binary at `PsychQuant/che-transport-mcp`. Worth knowing because they shape tool behavior:

- **Time zone**: All time strings emitted by tools are in Asia/Taipei (`+08:00`)
- **Empty ≠ error**: Tools return `{"matches": []}` / `{"trains": []}` etc. when no data matches — that's a legitimate result, not a tool failure. Errors (`isError: true`) are reserved for system-level issues (auth, network, rate limit, schema drift)
- **Cache TTL tiers**: 24h static (stations / routes / lots / CCTV) · 1h timetables · 5-10 min news · 0s live data
- **Rate limit**: TDX free tier = 50 req/min. 429 triggers single 1s retry; second 429 returns error
- **臺/台 bidirectional normalization**: Both query and candidate name are normalized before fuzzy matching
- **LRU cache cap**: default 1000 entries; long sessions won't grow unbounded
- **City required** for Bus / Parking tools (no fan-out — TDX rate limit + disambiguation)
- **Parallel fan-out** for `rail_search_stations` when system is unspecified — results stably re-sorted by `RailSystem.allCases` order

## Auth setup (first time)

The binary reads credentials from macOS keychain service `che-transport-tdx`. SessionStart hook surfaces credential presence + binary version. If credentials missing → invoke `/che-transport-mcp:setup-tdx`.

## Update flow

| Scenario | Action |
|----------|--------|
| Upgrade plugin shell only (skills / hooks / wrapper) | See **Plugin-shell-only changes** below |
| Upgrade binary version (full chain) | See **Full upgrade chain** below |
| Plugin not picking up changes | `Cmd+Q` Claude Code + reopen; closing the window is not enough for MCP servers |

### Two version fields — `version` vs `binaryVersion`

`plugin.json` carries **two** version numbers, deliberately decoupled:

| Field | Tracks | Read by |
|-------|--------|---------|
| `version` | The plugin **shell** (skills, hooks, wrapper, docs) | Claude Code marketplace / `claude plugin update` |
| `binaryVersion` | The **CheTransportMCP binary** release tag | `bin/che-transport-mcp-wrapper.sh` for auto-download |

This split exists because the wrapper downloads the binary release tagged `v$binaryVersion`. If the wrapper read `version`, a shell-only bump (e.g. new skill) would make it chase a binary release tag that doesn't exist → 404 → fallback-to-latest with a lying sidecar. Keeping `binaryVersion` separate means shell and binary cadences are independent. The wrapper falls back to `version` if `binaryVersion` is absent (older plugin.json files).

### Full upgrade chain (binary + plugin)

Triggered when there's a new binary release (new tools, bug fixes, or schema changes in the underlying Swift MCP). Three repos are touched in order:

1. **Source repo** `PsychQuant/che-transport-mcp`
   - Bump `Sources/CheTransportMCP/Version.swift` (`AppVersion.version = "X.Y.Z"`)
   - Bump `mcpb/manifest.json` version to match (build-mcpb.sh enforces parity)
   - Move CHANGELOG `[Unreleased]` content under `[X.Y.Z] — YYYY-MM-DD`
   - Commit + push
   - `export DEVELOPER_ID=F2523DCF6D02BE99B67C7D27F633119292DA4934 NOTARY_PROFILE=che-mcps-notary`
   - `make release-signed` (universal build → Developer ID sign → Apple notarize → pack .mcpb; ~2-10 min)
   - `git tag vX.Y.Z && git push --tags`
   - `gh release create vX.Y.Z mcpb/server/CheTransportMCP mcpb/server/CheTransportMCP.sha256 mcpb/che-transport-mcp-X.Y.Z.mcpb mcpb/che-transport-mcp-X.Y.Z.mcpb.sha256 --repo PsychQuant/che-transport-mcp --title "vX.Y.Z — …" --notes-file <notes>`
   - **Critical**: include the **raw `CheTransportMCP` binary** as a release asset, not just the `.mcpb`. The wrapper greps `browser_download_url` looking for `/CheTransportMCP"` — without the raw binary asset, auto-download fails (the .mcpb is a Claude Desktop bundle, not what the wrapper consumes)

2. **Marketplace repo** `PsychQuant/psychquant-claude-plugins`
   - Bump **both** `version` and `binaryVersion` in `plugins/che-transport-mcp/.claude-plugin/plugin.json` to `X.Y.Z` (a binary release moves both in lockstep)
   - Bump matching `version` in `.claude-plugin/marketplace.json`
   - Optionally refresh the description / keywords if the surface area changed
   - The fastest path: `/plugin-tools:plugin-update che-transport-mcp` — it bumps + commits + pushes + runs `claude plugin marketplace update` + `claude plugin update` automatically

3. **End-user side** (automatic, no action needed)
   - Wrapper sees `plugin.json.binaryVersion` ≠ `~/bin/.CheTransportMCP.version` sidecar
   - Re-downloads pinned tag `vX.Y.Z` from GitHub Release on next MCP spawn (atomic `.tmp + mv` swap)
   - Falls back to `releases/latest` if pinned tag missing
   - If anon GitHub API rate limit (60/hr) hit, wrapper preserves the existing binary instead of failing — graceful degradation

### Plugin-shell-only changes

If you only touched skills / hooks / wrapper / CLAUDE.md / README (no binary code change), skip Step 1 entirely:

- Bump only `version` in `plugin.json` (leave `binaryVersion` pinned to the current binary release)
- Bump the matching entry in `marketplace.json`
- `/plugin-tools:plugin-update che-transport-mcp`

Because the wrapper reads `binaryVersion` (not `version`), a shell-only `version` bump will NOT trigger a spurious binary re-download. Convention: shell-only bumps keep the binary's major.minor and add a patch — e.g. binary `binaryVersion: 0.2.0`, shell `version: 0.2.1`.

## References

- Source repo: <https://github.com/PsychQuant/che-transport-mcp>
- TDX register: <https://tdx.transportdata.tw/register>
- Design spec (in source repo): `docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md`
- NSQL discipline reference: <https://github.com/kiki830621/NSQL>
