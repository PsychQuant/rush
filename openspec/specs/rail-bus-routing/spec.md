# rail-bus-routing Specification

## Purpose

TBD - created by archiving change 'add-rail-bus-routing'. Update Purpose after archive.

## Requirements

### Requirement: Rail-to-bus multi-modal routing with an explicit transfer

The system SHALL provide a `rail_bus_route(from, to_stop, city, transfer?, depart_after?)` MCP tool that composes a rail leg with a final bus leg to `to_stop` within one `city`. The `transfer` parameter SHALL be optional. When `transfer` is provided, it SHALL be a rail station (TRA or TRTC) and the rail leg SHALL route `from` → `transfer`, then a name-matched bus stop at `transfer` SHALL carry the bus leg to `to_stop`. When `transfer` is omitted, the system SHALL auto-select the transfer hub (see the auto transfer-hub selection requirement). `to_stop` SHALL be a bus stop; `depart_after` defaults to now (Asia/Taipei). The result SHALL contain `legs[]` (rail legs then one bus leg, each with `mode` and `source`), `transfers[]` (the transfer station with `walk_min`), `arrival_time`, `duration_min`, and `transfer_count`. All emitted times SHALL be Asia/Taipei (`+08:00`).

#### Scenario: Rail then bus to the destination with explicit transfer

- **WHEN** `transfer` is provided AND `from` reaches `transfer` by rail AND a name-matched bus stop at `transfer` has a direct route to `to_stop`
- **THEN** the result SHALL contain the rail legs to `transfer`, a transfer entry at `transfer`, and a bus leg from the matched stop to `to_stop`, with the bus boarding at or after the rail arrival plus the transfer walk

#### Scenario: Rail leg unreachable

- **WHEN** `transfer` is provided AND no rail route exists from `from` to `transfer`
- **THEN** the result SHALL be `{ routes: [], note }`, not an error

##### Example: 中壢 → 台北轉乘 → 公車到目的地

- **GIVEN** `from = 中壢` (TRA), `transfer = 臺北` (rail), `to_stop` a bus stop on a route served by the `臺北車站(忠孝)` stop, `depart_after = 08:00`
- **WHEN** `rail_bus_route` runs
- **THEN** leg 1 is the TRA leg 中壢 → 臺北 (`source: live`), a transfer at 臺北 (`walk_min`), and leg 2 is the bus from `臺北車站(忠孝)` to `to_stop` boarding after the train arrives, with `arrival_time` from the bus timetable (or `null` + note if that bus route is frequency-only)

---
### Requirement: Name-matched bus-rail interchange

The bus stop used at the transfer SHALL be selected by matching its name (normalized `臺`→`台`) against patterns derived from the transfer station's name `X`: `捷運X站`, `X車站`, or `X火車站`. The system SHALL NOT match on the bare station name alone (which over-matches district-named stops), and SHALL NOT use geographic proximity.

#### Scenario: District-named stop rejected

- **WHEN** the transfer station is `南港`
- **THEN** a stop named `南港行政中心(南港車站)` SHALL match (via `X車站`) while a stop named `南港高工` SHALL NOT match

#### Scenario: Normalization across 臺/台

- **WHEN** the transfer station name is `臺北` and a bus stop is named `臺北車站(忠孝)`
- **THEN** the names SHALL match after normalizing `臺`→`台`

---
### Requirement: Honest post-transfer bus-leg timing

The bus leg SHALL be timed without A2 live ETA, because A2 is a now-snapshot and cannot predict the future-time boarding after the rail arrival. The bus board SHALL be the next timetabled departure at or after (rail arrival + transfer walk) with `source: scheduled`, or the headway expected wait `MinHeadwayMins/2` with `source: frequency` when the route has no timetable. The final `arrival_time` SHALL come from the bus timetable per-stop delta where the route is timetabled (`source: scheduled` on the bus leg), and SHALL be `null` with a note for frequency-only routes — never a fabricated value.

#### Scenario: Frequency-only bus leg omits arrival

- **WHEN** the selected bus route at the transfer has only headway data (no timetable)
- **THEN** the bus leg's board SHALL be a headway expected-wait (`source: frequency`) and the journey `arrival_time` SHALL be `null` with an explanatory note

---
### Requirement: Endpoint disambiguation follows NSQL discipline

When `from`, `transfer`, or `to_stop` matches more than one station/stop within the city, the tool SHALL return `{ matches: [...] }` for the ambiguous endpoint and SHALL NOT guess a single one or return a route.

#### Scenario: Ambiguous destination stop

- **WHEN** `to_stop` matches multiple bus stops in the city
- **THEN** the result SHALL be `{ matches: [...] }` enumerating the candidate stops, and SHALL NOT contain `legs`

---
### Requirement: Empty-is-not-error and graceful degradation

The tool SHALL treat "no rail→bus path" as the non-error result `{ routes: [], note }`, reserving errors for system-level failures (auth, network, rate limit). When no name-matched bus stop at the transfer has a direct route to `to_stop`, the result SHALL be `{ routes: [], note }`. When the bus schedule feed is unavailable, the board SHALL fall back to headway and arrival SHALL be omitted, without erroring.

#### Scenario: No qualifying transfer bus stop

- **WHEN** no name-matched bus stop at `transfer` serves a direct route to `to_stop`
- **THEN** the result SHALL be `{ routes: [], note }` rather than an error

---
### Requirement: Auto transfer-hub selection via reverse search

When `transfer` is omitted, the system SHALL auto-select the transfer hub by a `to_stop`-anchored reverse search: among the bus routes serving `to_stop`, for each route+direction it SHALL scan the stops upstream of `to_stop` (lower stop index, same direction) and name-match them to rail stations using the existing bus-rail name-match. Each match yields a candidate `(rail hub, boarding stop)` pair. The system SHALL deduplicate candidates by `(rail station, boarding stop)`, run the rail leg `from` → hub and the bus leg boarding → `to_stop` for each candidate, and return the itinerary with the earliest final arrival (known arrivals before unknown, then soonest board). The result SHALL include an `auto_selected_transfer` field naming the chosen hub's station. The candidate set SHALL be bounded by a cap; when the cap truncates candidates, the result SHALL carry a note disclosing how many were dropped (no silent truncation). The auto-hub path SHALL NOT change the explicit-transfer path.

#### Scenario: Auto-selected hub returns the earliest rail→bus itinerary

- **WHEN** `transfer` is omitted AND at least one bus route serving `to_stop` has an upstream stop that name-matches a rail station reachable from `from`
- **THEN** the result SHALL contain rail legs to the auto-selected hub, a transfer entry there, a bus leg to `to_stop`, and `auto_selected_transfer` naming that hub, chosen as the earliest final arrival across candidates

#### Scenario: No qualifying hub

- **WHEN** `transfer` is omitted AND no bus route serving `to_stop` has an upstream stop that name-matches a rail station reachable from `from`
- **THEN** the result SHALL be `{ routes: [], note }`, not an error

#### Scenario: Candidate cap truncation is disclosed

- **WHEN** `transfer` is omitted AND the reverse search finds more candidate hubs than the cap
- **THEN** the system SHALL keep the candidates closest upstream to `to_stop` up to the cap, select among them, and the result SHALL carry a note stating how many candidates were dropped
