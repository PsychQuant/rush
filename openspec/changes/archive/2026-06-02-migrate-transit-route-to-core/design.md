# Design: migrate transit_route onto RaptorCore (Stage 3c-ii.2)

## Context

`RaptorCore` (3c-ii.1) is a strategy ensemble proven equivalent to `transit_route`, but no tool calls it. This increment flips `transit_route` to delegate to the core — the first migration, behavior-preserving, gated by `transit_route`'s frozen test suite (`TransitToolsTests`). The migration pattern established here repeats for the other four tools in later increments.

## Decision: delegate the route call, reconstruct the same payload

`transit_route`'s executor today resolves endpoints, fetches datasets, calls `MultimodalRouter.route(...)`, and formats the result via its payload builder. The migration changes exactly one seam: the route call.

- The endpoint resolution + dataset fetch are unchanged.
- Replace `MultimodalRouter.route(...)` with `RaptorCore.plan(from:to:departAfterMin:inputs:strategies: [ComposedStrategy(), RaptorStrategy()])`, building `RoutingInputs` from the already-fetched `traConnections` + `MetroData` + `queryDate`.
- The returned `RaptorCore.Journey` is mapped back into the existing output payload. Because `ComposedStrategy` wins for `transit_route`'s ≤1-transfer journeys (it is the optimal floor; `RaptorStrategy` over-counts and cannot beat it) and `ComposedStrategy` IS `MultimodalRouter.route`, the journey is identical to today's — so the emitted JSON is byte-identical and `TransitToolsTests` passes unchanged.

### Journey must carry transfers

`transit_route`'s payload emits `transfers[]` (`at` / `at_name` / `walk_min`), but `RaptorCore.Journey` carries only `legs` + `arrivalMin`. So `Journey` gains `transfers: [MultimodalRouter.Transfer]`:
- `ComposedStrategy` sets it from `MultimodalRouter.Itinerary.transfers` (exact).
- `RaptorStrategy` sets it best-effort from its footpath edges (walk transfers). It is never the selected journey for `transit_route` fixtures, so its transfer fidelity does not affect equivalence; correctness of the *selected* journey's transfers comes from `ComposedStrategy`.

To minimize the `transit_route` edit, the executor reconstructs a `MultimodalRouter.Itinerary` from the selected `Journey` (legs, transfers, arrivalMin) and passes it to the **existing, unchanged** payload builder.

## In scope
Enriching `Journey` with `transfers` (+ both strategies populating it); rewiring `transit_route`'s executor route-call to `RaptorCore.plan`; reconstructing the existing payload from the `Journey`; a unit assertion that `ComposedStrategy`'s `Journey.transfers` mirror the itinerary's. Asia/Taipei times.

## Out of scope
Migrating any other tool; `journey_plan` / multi-transfer exposure; any behavior/output/accuracy change to `transit_route`; editing `TransitToolsTests` (the frozen oracle); changing `MultimodalRouter` / `MetroGraph` / `TimetableRouter` / the other four tools.

## Reuse
- `RaptorCore` / `ComposedStrategy` / `RaptorStrategy` (3c-ii.1) — unchanged except `Journey.transfers`.
- `MultimodalRouter.Itinerary` / `.Transfer` — the payload builder's input shape (reconstructed from the Journey).
- `transit_route`'s existing payload builder + endpoint resolution + fetch — unchanged.

## Risks & mitigations
- **Output drift** → `TransitToolsTests` (frozen) is the regression oracle; any byte difference fails it. The journey is identical because `ComposedStrategy` (= `MultimodalRouter.route`) wins.
- **RaptorStrategy accidentally selected** → it over-counts metro wait per hop, so for `transit_route`'s journeys it arrives no earlier than `ComposedStrategy`; on ties `ComposedStrategy` (registered first) wins. The equivalence harness from 3c-ii.1 already covers this; `TransitToolsTests` re-confirms end-to-end.
- **Regression to other tools** → only `RaptorCore.swift` + `TransitTools.swift` change; the other four tools and engines are untouched (git diff verifies).

## Implementation Contract
- **Observable**: `transit_route` returns the exact same JSON as before for every input — same legs, transfers, arrival_time, duration_min, transfer_count, matches/empty cases — now produced by routing through `RaptorCore.plan([ComposedStrategy, RaptorStrategy])`. Tool count stays 27; no schema/dispatch change.
- **Interface**: `RaptorCore.Journey` gains `transfers: [MultimodalRouter.Transfer]`; `ComposedStrategy`/`RaptorStrategy` populate it; `transit_route`'s executor calls `RaptorCore.plan` and reconstructs the payload from the `Journey`.
- **Failure modes**: no journey → same empty-routes + note as today; ambiguous endpoint → matches (unchanged, resolution is untouched).
- **Acceptance**: `TransitToolsTests` passes with NO edits to its file (the regression oracle); `RaptorCoreTests` gains an assertion that `ComposedStrategy.Journey.transfers` equal the itinerary's transfers; the 3c-ii.1 equivalence harness still passes; `git status` shows only `RaptorCore.swift` + `TransitTools.swift` + `RaptorCoreTests.swift` modified (no other tool/engine/test files); `swift build && swift test` green; smoke still 27 tools.
- **Scope boundary**: as In/Out scope — only `transit_route` migrates.
