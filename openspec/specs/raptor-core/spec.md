# raptor-core Specification

## Purpose

TBD - created by archiving change 'add-raptor-core'. Update Purpose after archive.

## Requirements

### Requirement: Strategy ensemble with dominance selection

The system SHALL provide an internal routing core that runs a set of independent routing strategies over the same inputs and returns the dominant journey. The dominance rule SHALL be: earliest arrival wins; ties broken by fewer transfers; remaining ties broken stably by strategy registration order. A strategy SHALL conform to a common `RoutingStrategy` interface so additional strategies can be added without changing the selector. The core SHALL be assembled from the same fetched inputs the existing routers use (TRA timetable + live board, metro headway + station-to-station travel, the interchange registry) and SHALL NOT introduce a new TDX endpoint.

#### Scenario: Selector picks the dominant journey

- **WHEN** two strategies return journeys with different arrival times
- **THEN** the core SHALL return the earlier-arriving one; and when arrivals tie, the one with fewer transfers

---
### Requirement: Proven-composition strategy as the floor

One strategy SHALL reproduce the existing TRA↔Taipei-Metro composition (delegating to the TRA timetable router, the metro graph with `headway/2` expected-wait, and the curated interchange registry). The journey selected by the ensemble SHALL never arrive later than this strategy's journey — that is, the proven composition is always a candidate, so the core cannot regress below it.

#### Scenario: Ensemble never regresses below the proven composition

- **WHEN** the ensemble routes any origin/destination for which the proven composition returns a journey
- **THEN** the selected journey's arrival SHALL be less than or equal to the proven composition's arrival

---
### Requirement: Round-based strategy for multi-transfer reachability

The system SHALL provide a round-based strategy that computes earliest arrival bounded by a configurable maximum round count, delegating intra-mode shortest paths to the proven sub-engines (TRA timetable, metro graph) and crossing modes only at curated interchange footpaths. It SHALL be able to reach a destination requiring two transfers when the maximum round count is at least 2, and SHALL NOT reach it when the bound is 1. Metro legs SHALL carry `source: frequency` with an expected wait of `headway/2`; TRA legs SHALL carry `source: live` or `scheduled`.

#### Scenario: Two-transfer destination needs the higher round bound

- **WHEN** a destination is reachable only after two transfers
- **THEN** the strategy with maximum round count at least 2 SHALL find it and with maximum round count 1 SHALL NOT

---
### Requirement: Equivalence to transit_route without rewiring

The ensemble SHALL reproduce `transit_route`'s journeys — the ordered legs (mode + endpoints + source), the arrival time, and the transfer count — for `transit_route`'s existing executor fixtures (TRA→metro, metro-only, TRA-only, and the empty/unreachable case). The core SHALL be internal: no MCP tool SHALL be added, removed, or rewired in this increment, and the five shipped routing tools SHALL retain their exact current behavior with no edits to their source.

#### Scenario: Ensemble reproduces a transit_route journey

- **WHEN** a `transit_route` fixture (e.g. 中壢 → 西門 via the 板橋 interchange) is replayed through the ensemble
- **THEN** the selected journey SHALL have the same legs (mode + endpoints + source), the same arrival time, and the same transfer count as `transit_route`'s output

#### Scenario: Shipped tools are untouched

- **WHEN** this increment is applied
- **THEN** the `transit_route`, `rail_bus_route`, `bus_rail_route`, `bus_route`, and `metro_find_route` tools SHALL behave identically to before and their test suites SHALL pass with no edits to their source files

---
### Requirement: Journey carries transfers

The unified `Journey` SHALL carry the transfer list (each with an interchange station, its name, and walk minutes) in addition to its legs and arrival, so a migrated tool can emit the same `transfers[]` it does today. The proven-composition strategy SHALL populate the transfer list from the composition's transfers. The round-based strategy SHALL populate it from its footpath edges.

#### Scenario: Composed strategy preserves transfers

- **WHEN** the proven-composition strategy returns a journey for a route with one interchange
- **THEN** the journey's transfer list SHALL contain that interchange (station, name, walk minutes), matching the composition's transfers

---
### Requirement: transit_route delegates to the routing core

`transit_route` SHALL produce its result by routing through the strategy ensemble (proven-composition floor + round-based strategy) rather than calling the composition directly, and its emitted output SHALL be byte-identical to its prior behavior for every input — same legs, transfers, arrival time, duration, transfer count, and the same `matches` / empty-routes cases. No MCP tool SHALL be added or removed (tool count unchanged), and `transit_route`'s schema and dispatch SHALL be unchanged. The `transit_route` test suite SHALL pass with no edits to its source (it is the regression oracle). No tool other than `transit_route` SHALL be migrated in this increment.

#### Scenario: transit_route output is unchanged after migration

- **WHEN** `transit_route` is invoked for any input after the migration
- **THEN** it SHALL return the same output as before, now produced by routing through the ensemble, and its frozen test suite SHALL pass without edits

#### Scenario: Only transit_route is migrated

- **WHEN** this increment is applied
- **THEN** `rail_bus_route`, `bus_rail_route`, `bus_route`, and `metro_find_route` SHALL still call their existing routing paths and SHALL be unchanged
