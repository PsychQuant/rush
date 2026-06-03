## ADDED Requirements

### Requirement: Delegating facades for single-mode tools

The routing core SHALL provide two delegating facades so single-mode tools dispatch through it without changing their multi-route output: a bus-direct facade that delegates to the proven bus router and returns its native option set, and a metro-routes facade that delegates to the proven metro graph's by-time and by-transfers searches and returns the native multi-route path set (nil results skipped). These facades SHALL NOT alter the delegated engines' output, and SHALL NOT route bus or metro through the round-based strategy. For single-mode tools the facade is structural routing-through-the-core, not ensemble or multi-transfer capability.

#### Scenario: Bus-direct facade delegates identically

- **WHEN** the bus-direct facade is called with the same candidates and live/schedule inputs as the bus router
- **THEN** it SHALL return the same option set the bus router returns directly

#### Scenario: Metro-routes facade delegates identically

- **WHEN** the metro-routes facade is called for an origin/destination
- **THEN** it SHALL return the by-time and by-transfers paths the metro graph returns directly (in that order, skipping nil)

### Requirement: All routing tools dispatch through the core

`rail_bus_route` and `bus_rail_route` SHALL compute their rail leg by routing through the strategy ensemble (via the shared rail-leg helper), and `bus_route` and `metro_find_route` SHALL compute their routes through the delegating facades. After this increment every routing tool dispatches through the core. Each tool's emitted output SHALL be byte-identical to its prior behavior, no MCP tool SHALL be added or removed (tool count unchanged), no tool schema or dispatch SHALL change, and each tool's test suite SHALL pass with no edits to its source.

#### Scenario: Each migrated tool's output is unchanged

- **WHEN** `rail_bus_route`, `bus_rail_route`, `bus_route`, or `metro_find_route` is invoked for any input after the migration
- **THEN** it SHALL return the same output as before, now produced by routing through the core, and its frozen test suite SHALL pass without edits

#### Scenario: The migration adds no new capability to single-mode tools

- **WHEN** `bus_route` or `metro_find_route` routes through its facade
- **THEN** it SHALL behave exactly as the proven bus router / metro graph would directly, gaining no multi-transfer or ensemble behavior
