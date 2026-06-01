## Why

Stage 3b of the (B) routing engine connects bus and rail — the first cross-mode journey that chains the two: "take TRA/metro to a transfer station, then a bus to the final destination". Stages 1–3a built the pieces (`rail_route`, `transit_route` for TRA↔metro, `bus_route` for direct bus); 3b composes them.

This is the engine's hardest, most accuracy-capped stage, so the first slice is deliberately tight: **`rail→bus` with an EXPLICIT transfer station** (the user names where to change modes — which matches real usage: "中壢搭台鐵到台北，再搭公車到 X"). That de-risks the combinatorial transfer-hub auto-selection (deferred to a follow-up) while still delivering the cross-mode composition + honest transfer timing. The bus↔rail interchange is found by **name-matching** — bus stops named `捷運<X>站` / `<X>車站` sit at rail station X (a live probe found ~14% of Taipei bus stops reference rail by name), avoiding both unscalable curation and noisy geo-matching.

## What Changes

- New MCP tool `rail_bus_route(from, transfer, to_stop, city, depart_after?)` — rail leg `from → transfer` (via the existing `transit_route` TRA↔TRTC engine, precise arrival + live delay), a walk transfer at the named station to a name-matched bus stop, then a bus leg to `to_stop` (via the `bus_route` engine), boarding after the rail arrival. Tool count 25 → 26.
- The bus boarding time uses the honest model from 3a: next timetabled departure at/after (rail arrival + walk) → `source: scheduled`, else headway/2 → `source: frequency`; A2 live ETA is NOT used for the bus leg because it is a now-snapshot and cannot predict a future-time boarding. The final arrival is the bus leg's timetable arrival where timetabled, otherwise omitted with a note.
- Reuses `MultimodalRouter` (rail leg) + `BusRouter` (bus leg) + a new name-matching interchange resolver. No new routing engine.

## Non-Goals

- **Automatic transfer-hub selection** — choosing the best rail station to change modes is deferred to Stage 3b-ii. This slice requires an explicit `transfer` station.
- **`bus→rail` direction** — only `rail→bus` (bus is the final leg) in this slice.
- **Multi-transfer** journeys (rail→bus→rail, two bus transfers, etc.).
- **Live bus ETA for the post-transfer leg** — A2's now-snapshot cannot time a future boarding; the bus leg uses schedule/headway. No faked precision.
- **Geo-proximity interchange matching** — name-matching only.
- **Rail systems beyond TRA + Taipei Metro** — the rail leg inherits `transit_route`'s scope (TRA + TRTC).
- **Changes to `transit_route` / `bus_route` contracts** — both stay frozen; `rail_bus_route` is a new tool reusing their cores.

## Capabilities

### New Capabilities

- `rail-bus-routing`: rail→bus multi-modal routing with an explicit transfer station, name-matched bus↔rail interchange, and honest schedule/headway bus-leg timing.

### Modified Capabilities

(none)

## Impact

- Affected specs: new capability `rail-bus-routing`
- Affected code:
  - New: Sources/CheTransportMCP/Tools/RailBusRouter.swift, Tests/CheTransportMCPTests/RailBusRouterTests.swift, Tests/CheTransportMCPTests/RailBusRouteToolTests.swift, Tests/CheTransportMCPTests/RailBusLiveTests.swift
  - Modified: Sources/CheTransportMCP/Tools/TransitTools.swift, Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift, CLAUDE.md, README.md, README_zh-TW.md, mcpb/manifest.json
  - Removed: (none)
