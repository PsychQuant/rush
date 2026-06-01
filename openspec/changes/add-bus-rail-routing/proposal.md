## Why

The (B) routing engine covers rail→bus (`rail_bus_route`, Stage 3b) but not its mirror: a journey that *starts* on a bus and *ends* on rail. Many real trips are exactly that — "from my bus stop to somewhere near a TRA/metro station". Stage 3c-i closes that gap with `bus_rail_route`.

The direction flip is not cosmetic; it improves accuracy. In rail→bus the bus is leg 2, boarding at a *future* time after the train arrives, so the live A2 ETA (a now-snapshot) is useless and we fall back to schedule/headway. In bus→rail the bus is **leg 1, boarding now** — so the A2 live ETA *applies*, making the first leg the most accurate leg in the whole engine.

This is the last slice composition can reach without a RAPTOR rewrite. Multi-transfer (bus→rail→bus) and a unified RAPTOR core stay deferred: the TDX data ceiling (metro/bus headway-only, no per-vehicle phase), not the algorithm, is the accuracy bound, and a speculative rewrite would risk regressing four shipped, tested, composing tools.

## What Changes

- New tool `bus_rail_route(from_stop, to, city, transfer?, depart_after?)` — the forward dual of `rail_bus_route`.
- Bus leg 1: board at `from_stop` now (or at `depart_after`); **A2 live ETA enabled** (`source: live`), falling back to schedule/headway when A2 is absent.
- Interchange discovery (forward): among the bus routes serving `from_stop`, scan stops *downstream* of `from_stop` and name-match them to TRA/TRTC rail stations → candidate alight-hubs. `transfer` optional: given → use that hub; omitted → auto-select.
- Rail leg 2: the `transit_route` engine from the alight-hub to `to`, anchored at `departAfter = bus arrival at the hub` (`source: live/scheduled/frequency`).
- Auto-hub selection mirrors 3b-ii: bounded candidate cap with honest disclosure; earliest final arrival wins; `auto_selected_transfer` names the chosen hub when auto.
- Output identical in shape to `rail_bus_route` but leg order reversed (bus leg then rail legs); `transfer_count` = 1. Tool count 26→27.

## Non-Goals

- **Multi-transfer** (bus→rail→bus, rail→rail→bus) — the genuine RAPTOR trigger; deferred until demonstrated demand.
- **Unified RAPTOR core** — a rewrite of the pairwise composers; deferred (data ceiling, not algorithm, is the bound).
- Geo-proximity hub matching; non-TRA/TRTC rail; changes to `rail_bus_route` / `transit_route` / `bus_route`.

## Capabilities

### New Capabilities

- `bus-rail-routing`: bus→rail multimodal routing with A2-live leg 1 and an explicit-or-auto name-matched alight-hub.

### Modified Capabilities

(none)

## Impact

- Affected specs: `bus-rail-routing` (new)
- Affected code:
  - New: Sources/CheTransportMCP/Tools/BusRailRouter.swift (pure: forward downstream-hub discovery + bus-then-rail stitch + earliest-across-hubs selection)
  - Modified: Sources/CheTransportMCP/Tools/TransitTools.swift (register bus_rail_route; executeBusRailRoute with explicit + auto branches)
  - New: Tests/CheTransportMCPTests/BusRailRouterTests.swift (downstream discovery, dedup, cap, selection)
  - New: Tests/CheTransportMCPTests/BusRailRouteToolTests.swift (executor: happy explicit, happy auto, ambiguous, no-hub, A2-live board)
  - New: Tests/CheTransportMCPTests/BusRailLiveTests.swift (env-cred gated live check)
  - Modified: Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift (tool count 26→27, bus_rail_route present)
  - Modified: CLAUDE.md, README.md, README_zh-TW.md, mcpb/manifest.json (bus_rail_route; tool count 27)
