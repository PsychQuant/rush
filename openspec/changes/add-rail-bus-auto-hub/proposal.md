## Why

`rail_bus_route` (Stage 3b-i) requires the caller to name the `transfer` station explicitly. That is a real burden: a user asking "中壢 to 市政府附近的某公車站" must already know which rail station to change modes at. Stage 3b-ii removes that requirement by auto-selecting the transfer hub — the last deferred piece of the rail↔bus slice.

The hard part is the combinatorial blow-up: naïvely, any rail station reachable from `from` could be the transfer, which would force a RAPTOR-class search we have deliberately deferred. The key insight that keeps this tractable is a **`to_stop`-anchored reverse search**: the only rail stations that can serve as the transfer are those that a *direct bus to `to_stop`* already passes through. Starting from `to_stop` and name-matching the upstream stops of its serving routes yields a small candidate set, not all of Taiwan — so auto-hub is a bounded loop over shipped 3b-i machinery, not a new engine.

## What Changes

- `rail_bus_route`'s `transfer` parameter becomes **optional**. When provided, the frozen 3b-i explicit-transfer path runs unchanged. When omitted, the new auto-hub path runs.
- Auto-hub path: from the bus routes serving `to_stop`, walk each route upstream from `to_stop`, name-match upstream stops to TRA/TRTC rail stations (reusing the 3b-i name-match), and collect the resulting `(hub, boarding-stop)` candidates. For each candidate, run the existing rail leg (`from → hub`) + bus leg + stitch, then return the **earliest-arrival** itinerary across candidates.
- The discovered candidate set is bounded by an explicit cap; when the cap truncates candidates, the result carries a disclosure note (no silent truncation).
- Tool count stays **26** (no new tool). The output shape is identical to 3b-i, plus an `auto_selected_transfer` marker naming which hub was chosen.

## Non-Goals

- `bus → rail` direction (symmetric but doubles the timing-anchor surface) — deferred.
- Multi-transfer / multi-leg routing — that is the unified RAPTOR core (3c), still deferred.
- Geo-proximity hub matching — name-match remains the only cross-mode-identity mechanism.
- Changing the explicit-transfer 3b-i behavior, or `transit_route` / `bus_route`.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `rail-bus-routing`: `transfer` becomes optional; adds auto transfer-hub selection via `to_stop`-anchored reverse search with a bounded, honestly-disclosed candidate cap.

## Impact

- Affected specs: `rail-bus-routing` (modified)
- Affected code:
  - Modified: Sources/CheTransportMCP/Tools/RailBusRouter.swift (new pure `candidateHubs` discovery + earliest-across-candidates selection)
  - Modified: Sources/CheTransportMCP/Tools/TransitTools.swift (make `transfer` optional in the tool schema; auto-branch in the rail_bus_route executor)
  - Modified: Tests/CheTransportMCPTests/RailBusRouterTests.swift (candidateHubs discovery + cap unit tests)
  - Modified: Tests/CheTransportMCPTests/RailBusRouteToolTests.swift (auto-hub executor cases)
  - Modified: Tests/CheTransportMCPTests/RailBusLiveTests.swift (auto-hub live case)
  - Modified: Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift (transfer no longer required in rail_bus_route schema)
  - Modified: CLAUDE.md, README.md, README_zh-TW.md, mcpb/manifest.json (rail_bus_route auto-hub behavior; tool count stays 26)
