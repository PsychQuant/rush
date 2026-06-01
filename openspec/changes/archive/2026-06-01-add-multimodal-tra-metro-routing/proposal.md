## Why

The (B) routing engine's north-star is an OpenTripPlanner/RAPTOR-class, MCP-native, Taiwan-deep transit substrate. Stage 1 (`rail_route`, v0.6.0) shipped TRA time-dependent earliest-arrival; `metro_find_route` (v0.5.0) does structural metro O/D with headway/2 wait estimates. But **no tool can route a journey that crosses modes** — e.g. 中壢 (TRA) → 西門 (Taipei Metro). That is the first capability neither existing tool can deliver, and it is the natural Stage 2: it forces the connection-model unification that Stage 3 (full multi-modal) builds on, while delivering real new user value now.

A `/spectra-discuss` session converged the design. The key constraint: TDX metro `Frequency` data gives frequency + time-bands but **no phase** (no actual departure epochs) — so synthesized fake departures and exact `next-departure` formulas are both dishonest. The only truthful model for metro legs is **expected-wait** (`E[wait] = current-band headway / 2`). Cross-system station identity is scoped to a **curated interchange registry** (a small hardcoded table) rather than algorithmic geo-matching, keeping the all-Taiwan station-identity problem out of scope.

## What Changes

- A new MCP tool `transit_route(from, to, depart_after?)` computing a TRA↔Taipei-Metro multi-modal time-dependent earliest-arrival itinerary, anchored to a departure clock time.
- `TimetableRouter` is extended from TRA-only discrete connection-scan to a **mixed scheduled + frequency** earliest-arrival model:
  - **Scheduled** connections (TRA, existing): discrete clock departures from `DailyTrainTimetable` + `TrainLiveBoard` live delay, `source: live`.
  - **Frequency** connections (metro, new): arrival at time `t` → boardable at `t + E[wait]`, where `E[wait]` is half the headway of the time band containing `t` (band-aware across peak/off-peak boundaries during a journey), `source: frequency`. No materialized departures.
- A **curated interchange registry** mapping known TRA↔TRTC transfer stations (e.g. 台北車站, 南港, 板橋, 松山) to their per-system station IDs plus a walk time.
- Tool count 23 → 24.

## Non-Goals

- **Not** extending `rail_route` (its TRA-only contract stays frozen) or `metro_find_route` (its structural-query contract stays frozen). Both remain untouched.
- **Not** bus, ferry, or any metro system other than Taipei Metro (TRTC). THSR inclusion is a design-time decision, not assumed here.
- **Not** algorithmic cross-system station identity (geo-matching, name-fuzzing). Only the curated interchange registry.
- **Not** per-vehicle metro live data — metro legs are expected-wait only; there is no metro `source: live`.
- **Not** Stage 3 (full multi-modal CSA + bus + full live feed). This stage proves the mixed model on one TRA↔TRTC corridor.

## Capabilities

### New Capabilities

- `multimodal-routing`: TRA↔Taipei-Metro time-dependent earliest-arrival routing over a mixed scheduled+frequency connection model, with a curated interchange registry and per-leg freshness labeling.

### Modified Capabilities

(none)

## Impact

- Affected specs: new capability `multimodal-routing`
- Affected code:
  - New: Sources/CheTransportMCP/Tools/MultimodalRouter.swift, Sources/CheTransportMCP/Tools/TransitTools.swift, Sources/CheTransportMCP/Tools/InterchangeRegistry.swift, Tests/CheTransportMCPTests/MultimodalRouterTests.swift, Tests/CheTransportMCPTests/TransitToolsTests.swift, Tests/CheTransportMCPTests/InterchangeRegistryTests.swift
  - Modified: Sources/CheTransportMCP/Tools/TimetableRouter.swift, Tests/CheTransportMCPTests/TimetableRouterTests.swift, Sources/CheTransportMCP/Server.swift, CLAUDE.md, README.md, README_zh-TW.md, mcpb/manifest.json
  - Removed: (none)
