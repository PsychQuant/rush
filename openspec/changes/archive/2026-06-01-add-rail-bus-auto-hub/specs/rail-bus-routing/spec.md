## MODIFIED Requirements

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

## ADDED Requirements

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
