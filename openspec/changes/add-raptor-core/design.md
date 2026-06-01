# Design: Unified routing core — increment 3c-ii.1 (strategy ensemble + transit_route equivalence)

## Context

The unified core will eventually subsume the five pairwise routers and enable ≥2-transfer journeys. A five-tool rewrite is only safe if behavior-preserving and incremental. The key design principle (user-directed): **the core is not one algorithm — it runs multiple routing strategies in parallel and returns the best journey by a dominance rule.** This dissolves the "reuse vs re-derive" dilemma: the proven engine becomes a *candidate*, not a *replacement*. This increment builds the ensemble + selector + two strategies and proves equivalence to `transit_route` on its fixtures — rewiring no tool. Recorded honestly: no demonstrated ≥2-transfer demand; the core adds reachable journeys, not accuracy.

## Decision: strategy ensemble + dominance selector

The core (`RaptorCore`) runs a set of independent strategies over the same inputs and selects the **dominant** journey:

- **Dominance rule**: earliest `arrival` wins; tie → fewer `transfer_count`; tie → stable (first strategy registered). This matches what every existing tool already optimizes (earliest arrival).
- **Why an ensemble, not one algorithm**: regression becomes structurally impossible — the ensemble is never worse than its best strategy, and the proven composition is always one of them. RAPTOR can only *add* reachable journeys (≥2 transfers); it can never make a ≤1-transfer answer worse, because it cannot beat the optimal earliest arrival the proven strategy already finds. We get the generality of a from-scratch RAPTOR and the safety of reusing the proven engines at once.

### Strategies (this increment)

1. **`ComposedStrategy`** — the floor. Delegates to the proven `TimetableRouter` (TRA CSA + live delay) + `MetroGraph` (metro, `headway/2` expected-wait) composed at `InterchangeRegistry` seams — i.e. exactly `MultimodalRouter.route`'s method. For ≤1-transfer journeys this is optimal, so it dominates and the ensemble returns its journey. This guarantees `transit_route` equivalence **by construction** (same sub-engines, same costs).
2. **`RaptorStrategy`** — round-based label-setting over the inter-modal seam graph (nodes = TRA stations + metro stations; edges = TRA connections, metro segments via `MetroGraph`, `InterchangeRegistry` footpaths), bounded by `maxRounds`. Its distinctive contribution is **reachability the composition cannot express** (≥2 transfers). It delegates intra-mode shortest paths to the same sub-engines so its costs agree with `ComposedStrategy`; for ≤1-transfer cases it cannot beat the floor.

A strategy conforms to `RoutingStrategy { func plan(...) -> Journey? }`; new strategies (CSA variant, A*, contraction) slot in later without touching the selector.

## Unified output model

- `Journey { legs: [Leg], arrivalMin: Int, transferCount: Int }` where `Leg` carries `mode` (TRA/Metro/Bus) + endpoints + `depMin`/`arrMin` + `source` (live/scheduled/frequency) — structurally `MultimodalRouter.Itinerary`/`Leg` so the differential harness compares directly and later increments can map tool outputs onto it.
- `RoutingInputs` bundles the already-fetched datasets each strategy needs (`traConnections`, `MetroData`, `queryDate`) — assembled from the SAME inputs the routers use today; no new TDX fetch.

## RAPTOR strategy mechanics

Round-based earliest-arrival (single criterion = arrival; transfers bounded by `maxRounds`):
- Round 0: origin reachable at `departAfterMin`.
- Round k: extend each stop improved in round k-1 by one mode-hop — relax TRA connections (earliest catchable), metro segments (`MetroGraph` from the entered node, entry wait `headway/2`), and `InterchangeRegistry` footpaths — keeping the earliest-arrival label per stop; parent pointers reconstruct legs.
- `maxRounds` default small; this increment validates a ≥2-transfer reachability case in a unit test, but no tool consumes multi-transfer output yet.

## In scope
`RaptorCore` ensemble + dominance selector + `ComposedStrategy` (floor, = `MultimodalRouter` method) + `RaptorStrategy` (round-based, ≥2-transfer-capable, delegating to sub-engines) over TRA + Taipei-Metro + curated transfers; unit tests for the selector dominance rule, the RAPTOR round reachability/earliest-arrival, and the floor guarantee; a differential harness proving the ensemble reproduces `transit_route`'s journeys on its existing fixtures. Asia/Taipei times.

## Out of scope
Rewiring `transit_route` or any tool to call the core (3c-ii.2+); a `journey_plan` ≥2-transfer tool; bus connections in the core; any accuracy change; THSR / non-TRTC metro; additional strategies beyond the two named.

## Reuse
- `TimetableRouter` (TRA CSA + live delay), `MetroGraph` (metro Dijkstra + `headway/2`), `InterchangeRegistry`, `MultimodalRouter.MetroData` — both strategies delegate intra-mode routing to these unchanged. `ComposedStrategy` reuses `MultimodalRouter`'s composition directly.
- `MultimodalRouter.Itinerary`/`Leg` — the shape `Journey` mirrors; the differential harness is a structural diff.

## Risks & mitigations
- **Ensemble could regress the proven engine** → impossible by the dominance rule: `ComposedStrategy`'s journey is always a candidate, so the selected journey is never later-arriving than it. A unit test asserts the floor (ensemble.arrival ≤ ComposedStrategy.arrival).
- **RAPTOR strategy diverges from the proven costs** → it delegates intra-mode shortest paths to the same `TimetableRouter`/`MetroGraph`, so per-leg costs agree; the selector picks whichever journey arrives earliest regardless.
- **Scope creep into a rewrite** → this increment rewires nothing; the five tools' code paths and tests are untouched (verified by their suites passing with zero edits).
- **Dead-code concern** → the core is exercised by its own tests + the differential harness; intentional staging, documented in CLAUDE.md.

## Implementation Contract
- **Observable**: a new internal `RaptorCore.plan(from:to:departAfterMin:inputs:strategies:)` that runs the registered strategies and returns the dominant `Journey` (earliest arrival; fewer-transfers tiebreak) — ordered legs with `mode`/`source`, `arrivalMin`, `transferCount`, structurally equivalent to `MultimodalRouter.Itinerary`. `ComposedStrategy` and `RaptorStrategy` both conform to `RoutingStrategy`. No MCP tool calls the core; no tool's schema, dispatch, or output changes. TRA legs `source: live/scheduled`; metro legs `source: frequency` (`headway/2`).
- **Interface**: `RoutingStrategy` protocol; `RaptorCore` (selector); `ComposedStrategy` (delegates to `MultimodalRouter` method — the floor); `RaptorStrategy` (round-based, delegates intra-mode to sub-engines, `maxRounds`-bounded). All internal; not registered as tools.
- **Failure modes**: no strategy returns a journey → nil (harness maps to `transit_route`'s empty-routes case); never throws on data gaps.
- **Acceptance**: `RaptorCoreTests` (dominance selector picks earliest-arrival then fewer-transfers; **floor guarantee** — ensemble.arrival ≤ ComposedStrategy.arrival on every fixture; `RaptorStrategy` reaches a ≥2-transfer destination that a 1-round bound does not); `RaptorTransitEquivalenceTests` (for each `transit_route` fixture — TRA→metro happy, metro-only, TRA-only, empty — the ensemble's journey legs/arrival/transfer_count equal `transit_route`'s output); the FIVE shipped tools' suites pass UNCHANGED (no edits to their files); `swift build && swift test` green.
- **Scope boundary**: as In/Out scope. Rewiring, journey_plan, bus-in-core, accuracy changes, extra strategies are explicitly excluded and belong to later increments.
