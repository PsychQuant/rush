## Summary

Rewire `transit_route` to route through `RaptorCore` (the strategy ensemble) instead of calling `MultimodalRouter.route` directly — the first tool migration of Stage 3c-ii, behavior-preserving and gated by the frozen `transit_route` test suite.

## Motivation

3c-ii.1 landed `RaptorCore` as a strategy ensemble and proved (via a differential oracle) that it reproduces `transit_route`'s journeys — but no tool calls it; it is dead-code-until-wired. 3c-ii.2 begins the migration: flip `transit_route` to delegate to the core. This validates the migration pattern on the tool the oracle already covers, with the lowest possible risk, before the remaining four tools follow in later increments. The honest framing is unchanged: this flips plumbing — no behavior, output, or accuracy change.

## Proposed Solution

1. Enrich `RaptorCore.Journey` with `transfers: [MultimodalRouter.Transfer]` (it currently carries only `legs` + `arrivalMin`, but `transit_route`'s payload emits `transfers` with `at`/`at_name`/`walk_min`). `ComposedStrategy` populates it from `MultimodalRouter.Itinerary.transfers`; `RaptorStrategy` populates it best-effort from its footpath edges (it is not the selected journey for `transit_route` fixtures, so its transfer fidelity does not affect equivalence).
2. In `transit_route`'s executor, replace the direct `MultimodalRouter.route(...)` call with `RaptorCore.plan(strategies: [ComposedStrategy(), RaptorStrategy()])`, then reconstruct the existing output payload from the returned `Journey` (legs + transfers + arrival) so the emitted JSON is byte-identical.
3. The `transit_route` test suite is NOT edited — it is the regression oracle. Its assertions must pass unchanged, proving the migration preserved behavior.

The other four tools (`rail_bus_route`, `bus_rail_route`, `bus_route`, `metro_find_route`) are NOT migrated here.

## Non-Goals

- Migrating any tool other than `transit_route`.
- A `journey_plan` ≥2-transfer tool, or exposing multi-transfer output through `transit_route` (it stays single-transfer-scoped; the ensemble's RAPTOR strategy cannot beat the proven floor for these journeys).
- Any behavior, output-shape, or accuracy change to `transit_route`.
- Editing the `transit_route` test suite (it is the frozen oracle).
- Changing `MultimodalRouter`, `MetroGraph`, `TimetableRouter`, or the other tools.

## Impact

- Affected specs: `raptor-core` (modified — Journey carries transfers; transit_route delegates to the core)
- Affected code:
  - Modified: Sources/CheTransportMCP/Tools/RaptorCore.swift (Journey gains `transfers`; ComposedStrategy + RaptorStrategy populate it)
  - Modified: Sources/CheTransportMCP/Tools/TransitTools.swift (executeRoute delegates to RaptorCore.plan; payload reconstructed from Journey)
  - Modified: Tests/CheTransportMCPTests/RaptorCoreTests.swift (assert ComposedStrategy.Journey.transfers mirror the itinerary's)
  - Removed: (none)
