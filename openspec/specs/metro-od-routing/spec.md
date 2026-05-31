# metro-od-routing Specification

## Purpose

TBD - created by archiving change 'add-metro-od-direct-routing'. Update Purpose after archive.

## Requirements

### Requirement: Metro routing endpoints in the registry

The metro routing endpoints (station-of-route, station-to-station travel time, frequency, line) SHALL be defined in the single endpoint registry, and production code SHALL resolve their paths through the registry rather than embedding path string literals. Each non-static metro routing endpoint SHALL be covered by the live contract-test enumeration.

#### Scenario: Metro endpoints resolved through the registry

- **WHEN** the routing tool constructs a request to a metro endpoint
- **THEN** it obtains the path from the registry, and the contract-test enumeration includes that endpoint

#### Scenario: Metro path drift fails the contract test

- **WHEN** a metro routing endpoint path no longer matches the current TDX API
- **THEN** the contract test fails on the not-404 or 200 assertion

---
### Requirement: Metro O/D routing tool

The system SHALL provide an MCP tool that, given an origin station ID, a destination station ID, and a metro system code, returns the shortest route(s) connecting the two stations within that metro system, including routes that require one or more line transfers. The tool SHALL model the metro network as a graph — stations as nodes, same-line adjacent-station edges weighted by station-to-station travel time, and transfer edges weighted by inter-line transfer walking time — and SHALL return routes ordered by total travel time. Each route SHALL be expressed as an ordered list of legs (one leg per line ridden), each leg carrying its line name and per-leg travel time, together with the transfer points between legs. Each transfer point SHALL carry a walking time (hard data from the transfer dataset) and an estimated boarding wait derived from the current-period headway. A direct route SHALL be represented as a single-leg, zero-transfer route. Metro systems run on headways, not fixed timetables, so the tool SHALL NOT return a specific departure time.

#### Scenario: Direct route is a zero-transfer shortest path

- **WHEN** the two stations lie on a single line and that is the shortest path
- **THEN** the tool returns a route with one leg and zero transfers, carrying the line name, the accumulated travel time, and the current-period headway

##### Example:

- **GIVEN** origin = Taipei Main Station (BL12), destination = Nangang (BL22), system = TRTC
- **WHEN** metro_find_route is called
- **THEN** the result contains a single-leg route on the Bandu (板南) line with transfer_count = 0 and a travel-time value

#### Scenario: Transfer route required

- **WHEN** the two stations do not share a single line, so reaching the destination requires changing lines
- **THEN** the tool returns one or more multi-leg routes, each listing the lines ridden in order and the transfer station(s) between them, with each transfer carrying a walking time and an estimated boarding wait, and a total travel time that is the sum of the per-leg travel times and the per-transfer costs

##### Example:

- **GIVEN** origin = Taipei Main Station, destination = Tamsui (淡水), system = TRTC
- **WHEN** metro_find_route is called
- **THEN** the result contains a route with transfer_count >= 1 (e.g. ride the Bandu line, change to the Tamsui-Xinyi line at an interchange station), where the transfer carries a walking time and an estimated wait

#### Scenario: Candidates ordered by total time

- **WHEN** more than one route connects the two stations
- **THEN** the tool returns up to three candidates ordered by ascending total travel time, each annotated with its transfer count, and if the fewest-transfer route differs from the fastest route it is included among the candidates

#### Scenario: Unreachable or transfer-less system

- **WHEN** no path connects the two stations within the system (graph disconnected, or a single-line system with no transfer data and the stations are not on one line)
- **THEN** the tool returns an empty route list plus a note rather than an error (empty is not an error)
