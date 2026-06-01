## ADDED Requirements

### Requirement: Direct-route within-city bus routing

The system SHALL provide a `bus_route(from_stop, to_stop, city, depart_after?)` MCP tool that returns the direct bus routes serving both stops within one `city`, each annotated with a board time and (where available) an arrival time. `city` is required (a BusCity code); `depart_after` defaults to now (Asia/Taipei). A direct route qualifies only when a single route/sub-route serves the origin and destination stops in the same `Direction` with the origin's stop sequence before the destination's. The result SHALL be `{ routes: [...] }`, each entry carrying `route_name`, `direction`, `board_stop`, `alight_stop`, `board_in_min` (+`board_source`), and `arrival_time` (+`arrival_source`). All emitted times SHALL be Asia/Taipei (`+08:00`).

#### Scenario: Direct route exists

- **WHEN** `bus_route` is called with two stops served in order by at least one route
- **THEN** the result SHALL list each such route with its board time at the origin stop and, when the route is timetabled, its arrival time at the destination stop

#### Scenario: No direct route

- **WHEN** no single route serves both stops in the correct direction and sequence
- **THEN** the result SHALL be `{ routes: [], note }` where the note states that transfers are not yet supported, and SHALL NOT be an error

##### Example: 兩站直達

- **GIVEN** `from_stop` and `to_stop` are both served by route 671 (direction 0), origin sequence 5, destination sequence 12, and route 671 is timetabled
- **WHEN** `bus_route(from_stop, to_stop, city=Taipei, depart_after=08:00)` runs
- **THEN** `routes` contains an entry for 671 with `board_in_min` from live A2 (or the next scheduled departure) and `arrival_time` = board + the timetable ride-time (dest `ArrivalTime` − origin `DepartureTime` of the next trip), `arrival_source: scheduled`

### Requirement: Live board-ETA with honest fallback

The board time SHALL be taken from the `A2 EstimatedTimeOfArrival` live ETA at the origin stop for that route and direction when a live prediction exists, labeled `board_source: live`. When no live prediction exists, the board time SHALL fall back to the next timetabled departure (`board_source: scheduled`) for timetabled routes, or to the expected wait `MinHeadwayMins/2` of the current headway band (`board_source: frequency`) for frequency-only routes.

#### Scenario: Live ETA available

- **WHEN** A2 returns an `EstimateTime` for the route at the origin stop
- **THEN** `board_in_min` SHALL be that ETA (seconds converted to minutes) with `board_source: live`

#### Scenario: No live ETA, frequency-only route

- **WHEN** A2 has no prediction for the route at the origin stop and the route has only `Frequencys`
- **THEN** `board_in_min` SHALL be `MinHeadwayMins/2` of the band containing the current time with `board_source: frequency`

### Requirement: Timetable-backed arrival or honest omission

Arrival time SHALL be computed only from `Bus/Schedule` `Timetables` per-stop deltas. For a timetabled route, `arrival_time` SHALL be the board time plus the ride-time (destination-stop `ArrivalTime` minus origin-stop `DepartureTime` of the selected trip), with `arrival_source: scheduled`. For a frequency-only route, `arrival_time` SHALL be `null` with a note, and SHALL NOT be a fabricated or estimated value. The board time SHALL be provided regardless of arrival availability.

#### Scenario: Frequency-only route omits arrival

- **WHEN** a candidate route has only `Frequencys` (no `Timetables`)
- **THEN** its `arrival_time` SHALL be `null` with an explanatory note, while `board_in_min` is still provided

### Requirement: Stop disambiguation follows NSQL discipline

When `from_stop` or `to_stop` matches more than one stop within the city, the tool SHALL return `{ matches: [...] }` enumerating the candidate stops for user disambiguation, and SHALL NOT guess a single stop or return routes.

#### Scenario: Ambiguous stop name

- **WHEN** `from_stop` matches multiple stops in the city
- **THEN** the result SHALL be `{ matches: [...] }` with enough detail (stop id, name, position) to disambiguate, and SHALL NOT contain `routes`

### Requirement: Empty-is-not-error and graceful degradation

The tool SHALL treat "no direct route" as the non-error result `{ routes: [], note }`, reserving errors for system-level failures (auth, network, rate limit). When the A2 feed is unavailable, board times SHALL fall back to schedule/headway rather than erroring. When the schedule feed is unavailable, board times SHALL still come from A2 where present and arrival SHALL be omitted.

#### Scenario: A2 feed unavailable

- **WHEN** the `EstimatedTimeOfArrival` fetch fails or returns empty
- **THEN** board times SHALL fall back to timetable departures or headway expected-wait, and the tool SHALL NOT surface an error
