## ADDED Requirements

### Requirement: Journey carries transfers

The unified `Journey` SHALL carry the transfer list (each with an interchange station, its name, and walk minutes) in addition to its legs and arrival, so a migrated tool can emit the same `transfers[]` it does today. The proven-composition strategy SHALL populate the transfer list from the composition's transfers. The round-based strategy SHALL populate it from its footpath edges.

#### Scenario: Composed strategy preserves transfers

- **WHEN** the proven-composition strategy returns a journey for a route with one interchange
- **THEN** the journey's transfer list SHALL contain that interchange (station, name, walk minutes), matching the composition's transfers

### Requirement: transit_route delegates to the routing core

`transit_route` SHALL produce its result by routing through the strategy ensemble (proven-composition floor + round-based strategy) rather than calling the composition directly, and its emitted output SHALL be byte-identical to its prior behavior for every input — same legs, transfers, arrival time, duration, transfer count, and the same `matches` / empty-routes cases. No MCP tool SHALL be added or removed (tool count unchanged), and `transit_route`'s schema and dispatch SHALL be unchanged. The `transit_route` test suite SHALL pass with no edits to its source (it is the regression oracle). No tool other than `transit_route` SHALL be migrated in this increment.

#### Scenario: transit_route output is unchanged after migration

- **WHEN** `transit_route` is invoked for any input after the migration
- **THEN** it SHALL return the same output as before, now produced by routing through the ensemble, and its frozen test suite SHALL pass without edits

#### Scenario: Only transit_route is migrated

- **WHEN** this increment is applied
- **THEN** `rail_bus_route`, `bus_rail_route`, `bus_route`, and `metro_find_route` SHALL still call their existing routing paths and SHALL be unchanged
