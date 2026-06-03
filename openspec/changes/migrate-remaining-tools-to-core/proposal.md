## Summary

Route the remaining four tools (`rail_bus_route`, `bus_rail_route`, `bus_route`, `metro_find_route`) through `RaptorCore`, completing Stage 3c-ii — behavior-preserving, each gated by its frozen test suite.

## Motivation

3c-ii.2 migrated `transit_route`. This increment finishes the migration so ALL routing dispatches through `RaptorCore`, the precondition for a later `journey_plan` (≥2-transfer) tool. The pattern fits the two multi-modal composers cleanly; the two single-mode tools need delegating facades. An honest caveat is recorded so the work is not oversold.

## Proposed Solution

1. **rail_bus_route + bus_rail_route** — migrate the shared `composeRailLeg` helper's internal `MultimodalRouter.route` call to `RaptorCore.plan([ComposedStrategy(), RaptorStrategy()])` and reconstruct the `Itinerary` from the returned `Journey`. One edit covers both tools' rail legs (the same single-seam pattern as `transit_route`). `ComposedStrategy` wins for these ≤1-transfer rail legs, so behavior is identical.
2. **bus_route** — add a delegating facade `RaptorCore.planBusDirect(...)` that calls `BusRouter.route` and returns its native option set; `bus_route` calls the facade and formats its UNCHANGED payload.
3. **metro_find_route** — add a delegating facade `RaptorCore.planMetroRoutes(...)` that calls the metro graph's by-time + by-transfers searches and returns the native multi-route path set; `metro_find_route` calls the facade and formats its UNCHANGED payload.

Each tool's frozen test suite is NOT edited — they are the regression oracles. The five frozen test files prove byte-identical behavior.

## Non-Goals

- Any behavior, output-shape, or accuracy change to any of the four tools.
- A `journey_plan` ≥2-transfer tool (follows once all tools dispatch through the core).
- Adding a full bus/metro time-dependent connection model to the RAPTOR round engine — the single-mode facades delegate to the proven `BusRouter` / metro graph, they do NOT make bus/metro reachable through `RaptorStrategy`'s rounds.
- Editing any tool's test suite (all four are frozen oracles).
- Exposing multi-transfer output through any of these four tools.

## Honest caveat (recorded, not oversold)

For the single-mode tools (`bus_route`, `metro_find_route`) the facade is **structural routing-through-the-core — delegation to the proven engine, not ensemble or multi-transfer capability**. These tools are bus-only / metro-only (0–1 transfer) and gain nothing functional from `RaptorCore`; the value is uniformity (all routing now dispatches through one core), which sets up `journey_plan`. The multi-transfer value of the ensemble applies only to the multi-modal composers.

## Impact

- Affected specs: `raptor-core` (modified — adds delegating facades; all five tools dispatch through the core)
- Affected code:
  - Modified: Sources/CheTransportMCP/Tools/RaptorCore.swift (add `planBusDirect` + `planMetroRoutes` delegating facades)
  - Modified: Sources/CheTransportMCP/Tools/TransitTools.swift (composeRailLeg rail leg → RaptorCore.plan; covers rail_bus_route + bus_rail_route)
  - Modified: Sources/CheTransportMCP/Tools/BusTools.swift (bus_route routes through RaptorCore.planBusDirect)
  - Modified: Sources/CheTransportMCP/Tools/MetroTools.swift (metro_find_route routes through RaptorCore.planMetroRoutes)
  - Modified: Tests/CheTransportMCPTests/RaptorCoreTests.swift (assert the facades delegate identically to the proven engines)
  - Removed: (none)
