# Design: migrate the remaining four tools onto RaptorCore (Stage 3c-ii.3)

## Context

3c-ii.2 migrated `transit_route` through `RaptorCore`. This increment routes the other four tools through the core so ALL routing dispatches through it (the precondition for a future `journey_plan`). Two of the four fit the single-seam `RaptorCore.plan` pattern; two are single-mode multi-route tools that need delegating facades. Behavior is byte-identical throughout; each tool's frozen test suite is the regression oracle. Honest caveat recorded: for the single-mode tools the facade is structural delegation, not new capability.

## Decision: one clean seam + two delegating facades

### A. rail_bus_route + bus_rail_route — the shared composeRailLeg seam
Both tools compute their rail leg via the shared `composeRailLeg` helper, whose single internal `MultimodalRouter.route` call is the same seam `transit_route` had. Replace that call with `RaptorCore.plan([ComposedStrategy(), RaptorStrategy()])` and reconstruct the `MultimodalRouter.Itinerary` from the returned `Journey` (legs + transfers + arrival). One edit migrates both tools' rail legs. `ComposedStrategy` is optimal for the ≤1-transfer rail legs, so the journey is identical → both tools' output is unchanged.

### B. bus_route — delegating facade RaptorCore.planBusDirect
`bus_route` uses `BusRouter.route` (bus-only). `RaptorCore.plan` returns one dominant `Journey`, which cannot express `bus_route`'s native multi-route option set (board source, nullable arrival). So add a thin facade `RaptorCore.planBusDirect(candidates:a2BySig:scheduleBySig:nowMin:departAfterMin:weekday:) -> [BusRouter.Option]` that delegates to `BusRouter.route` and returns its result unchanged. `bus_route` calls the facade instead of `BusRouter.route` directly; its payload builder is untouched → byte-identical.

### C. metro_find_route — delegating facade RaptorCore.planMetroRoutes
`metro_find_route`'s `candidateRoutes` runs `graph.shortestPathByTime` + `graph.shortestPathByTransfers` (two searches → a multi-route set). Add a thin facade `RaptorCore.planMetroRoutes(graph:from:to:) -> [MetroGraph.Path]` that returns `[byTime, byTransfers]` (the same two searches, same order, nil-skipped). `candidateRoutes` calls the facade instead of the two inline searches; dedup/assembly/sort/cap downstream are untouched → byte-identical.

## Why facades, not RaptorStrategy rounds, for the single-mode tools
`RaptorStrategy`'s round engine only models TRA + metro time-dependent connections; it has no bus connections, and metro is reached only via the interchange seam. Making `bus_route`/`metro_find_route` route through `RaptorStrategy` rounds would require a full bus connection model + a multi-route round variant — large new scope, for tools that are single-mode (0–1 transfer) and gain nothing from the ensemble. The facade delegates to the proven engine: same output, no new core scope. This is the honest minimum that satisfies "all routing dispatches through RaptorCore."

## In scope
The composeRailLeg seam migration (rail_bus_route + bus_rail_route); `RaptorCore.planBusDirect` + `RaptorCore.planMetroRoutes` delegating facades; `bus_route` + `metro_find_route` routing through them; facade unit tests asserting identical delegation; all four tools' frozen suites pass unedited.

## Out of scope
Any behavior/output/accuracy change; `journey_plan`; a bus/metro connection model in the round engine; editing any tool test suite; multi-transfer exposure through these four tools.

## Reuse
- `RaptorCore.plan` / `ComposedStrategy` / `RaptorStrategy` (3c-ii.1/.2) — the rail-leg seam reuses them unchanged.
- `BusRouter.route` (bus_route's proven engine) — `planBusDirect` delegates to it.
- `MetroGraph.shortestPathByTime` / `shortestPathByTransfers` (metro_find_route's proven engine) — `planMetroRoutes` delegates to them.
- All four tools' payload builders + endpoint resolution + fetch — unchanged.

## Risks & mitigations
- **Output drift on any tool** → each tool's frozen test suite (`RailBusRouteToolTests`, `BusRailRouteToolTests`, `BusRouteToolTests`, `MetroToolsTests`) is the regression oracle; any byte difference fails it.
- **composeRailLeg shared by 3 call sites** → all three (explicit rail_bus, auto rail_bus, bus_rail) route through the same migrated helper; both tools' suites cover them.
- **Facade is ceremonial for single-mode tools** → acknowledged and recorded as the honest caveat; the facade adds no behavior, only a dispatch indirection through the core.
- **Regression to transit_route** → its seam is unchanged this increment; its frozen suite still passes.

## Implementation Contract
- **Observable**: all four tools return byte-identical JSON to before, now produced by routing through `RaptorCore` — `rail_bus_route`/`bus_rail_route` via `composeRailLeg → RaptorCore.plan`; `bus_route` via `RaptorCore.planBusDirect`; `metro_find_route` via `RaptorCore.planMetroRoutes`. Tool count stays 27; no schema/dispatch change to any tool.
- **Interface**: `RaptorCore.planBusDirect(candidates:a2BySig:scheduleBySig:nowMin:departAfterMin:weekday:) -> [BusRouter.Option]` (delegates to `BusRouter.route`); `RaptorCore.planMetroRoutes(graph:from:to:) -> [MetroGraph.Path]` (returns `[byTime, byTransfers]`, nil-skipped); `composeRailLeg` internally calls `RaptorCore.plan`.
- **Failure modes**: unchanged per tool — empty routes + note / matches as today; facades return empty arrays when the proven engine does; never throw on data gaps.
- **Acceptance**: `RailBusRouteToolTests`, `BusRailRouteToolTests`, `BusRouteToolTests`, `MetroToolsTests` all pass with NO edits to their files (the four oracles); `RaptorCoreTests` gains assertions that `planBusDirect` equals `BusRouter.route` and `planMetroRoutes` equals the two graph searches on the same inputs; `transit_route`'s suite + the equivalence harness still pass; `git status` shows only `RaptorCore.swift`, `TransitTools.swift`, `BusTools.swift`, `MetroTools.swift`, `RaptorCoreTests.swift` modified (no tool test files); `swift build && swift test` green; smoke still 27 tools.
- **Scope boundary**: as In/Out scope — four tools migrate; single-mode facades are delegation only.
