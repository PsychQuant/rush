# metro-od-routing Specification

## Purpose

TBD - created by archiving change 'add-metro-od-direct-routing'. Update Purpose after archive.

## Requirements

### Requirement: Metro direct O/D routing tool

The system SHALL provide an MCP tool that, given an origin station ID, a destination station ID, and a metro system code, returns the direct route(s) that connect the two stations on a single line. Each returned route SHALL include the line name, the station-to-station travel time, and the current-period service headway. Metro systems run on headways, not fixed timetables, so the tool SHALL NOT attempt to return a specific departure time.

#### Scenario: Direct route exists

- **WHEN** the tool is called with two stations that lie on a single metro route
- **THEN** it returns that route with its line name, the accumulated travel time between the two stations, and the headway for the current service period

##### Example:

- **GIVEN** origin = Taipei Main Station, destination = Nangang, system = TRTC
- **WHEN** metro_find_route is called
- **THEN** the result contains the Bandu (板南) line as a direct route with a travel-time value and a headway value

#### Scenario: No direct route

- **WHEN** the two stations do not share any single route (a transfer would be required)
- **THEN** the tool returns an empty route list rather than an error, and indicates that a transfer is needed (out of scope for this capability)

#### Scenario: Sparse-data system

- **WHEN** a metro system returns no travel-time or headway data for the queried route
- **THEN** the tool returns the route with empty/sentinel time and headway fields rather than failing (empty is not an error)

---
### Requirement: Metro routing endpoints in the registry

The metro routing endpoints (station-of-route, station-to-station travel time, frequency, line) SHALL be defined in the single endpoint registry, and production code SHALL resolve their paths through the registry rather than embedding path string literals. Each non-static metro routing endpoint SHALL be covered by the live contract-test enumeration.

#### Scenario: Metro endpoints resolved through the registry

- **WHEN** the routing tool constructs a request to a metro endpoint
- **THEN** it obtains the path from the registry, and the contract-test enumeration includes that endpoint

#### Scenario: Metro path drift fails the contract test

- **WHEN** a metro routing endpoint path no longer matches the current TDX API
- **THEN** the contract test fails on the not-404 or 200 assertion
