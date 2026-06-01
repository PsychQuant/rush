## ADDED Requirements

### Requirement: Multi-modal TRA↔Metro earliest-arrival routing

The system SHALL provide a `transit_route(from, to, depart_after?)` MCP tool that computes a single earliest-arrival itinerary spanning Taiwan Railway (TRA) and Taipei Metro (TRTC), anchored to a departure clock time (`depart_after`, default = now in Asia/Taipei). The result SHALL contain `legs[]` (each with `mode`, `from_station`, `to_station`, `dep_time`, `arr_time`, `source`), `transfers[]`, `arrival_time`, `duration_min`, and `transfer_count`. All emitted times SHALL be Asia/Taipei (`+08:00`).

#### Scenario: TRA-to-Metro journey via an interchange

- **WHEN** `transit_route` is called with a TRA origin and a metro-only destination reachable through a registered interchange
- **THEN** the result SHALL contain a TRA leg from the origin to the interchange, a transfer at the interchange, and a metro leg from the interchange to the destination, with `transfer_count` equal to the number of mode/line changes

#### Scenario: Metro-only journey

- **WHEN** both `from` and `to` resolve to TRTC metro stations
- **THEN** the result SHALL contain only metro legs and SHALL NOT require any TRA timetable fetch

##### Example: 中壢 → 西門 departing 08:00

- **GIVEN** `from = 中壢` (TRA), `to = 西門` (TRTC 板南線), `depart_after = 08:00`
- **WHEN** `transit_route` runs
- **THEN** leg 1 is TRA 中壢 → 台北 (`source: live`), a transfer at 台北車站 (`walk_min`), leg 2 is Metro 板南線 台北車站 → 西門 (`source: frequency`), and the result reports `transfer_count: 1` with `arrival_time` and `duration_min` set

### Requirement: Expected-wait frequency model for metro legs

Metro legs SHALL be modeled with an expected-wait frequency cost: arriving at a metro boarding point at time `t`, the boardable time SHALL be `t + E[wait]` where `E[wait]` is half the `MinHeadwayMins` of the headway band of that line containing `t` (selected by Asia/Taipei weekday → `ServiceDay` → band `StartTime`/`EndTime`, fixed at metro-entry time). Metro legs SHALL be labeled `source: frequency`. The system SHALL NOT fabricate discrete metro departure times, because TDX metro frequency data supplies frequency and time-bands but no departure phase.

#### Scenario: Peak-band headway applied

- **WHEN** a metro leg is boarded at a clock time falling inside a peak headway band
- **THEN** the expected wait SHALL be computed from that band's `MinHeadwayMins`, not a different band's

#### Scenario: Headway band selected at metro entry

- **WHEN** a journey enters the metro at a clock time falling within a given headway band
- **THEN** the expected wait for the metro portion SHALL be computed from that band's `MinHeadwayMins` (the band is fixed at metro-entry time; mid-metro band changes are out of scope as metro legs are short)

### Requirement: Live-delay-adjusted TRA legs

TRA legs SHALL apply `TrainLiveBoard` `DelayTime` to the scheduled `DailyTrainTimetable` connection before earliest-arrival selection, and SHALL be labeled `source: live` when live data is present or `source: scheduled` when it is not. A train that is delayed enough MAY be superseded by a later on-time train that arrives earlier.

#### Scenario: Live delay changes the chosen TRA leg

- **WHEN** the earliest-by-schedule TRA train is reported sufficiently delayed by `TrainLiveBoard`
- **THEN** the router MAY select a later scheduled train whose live-adjusted arrival is earlier, and the chosen leg SHALL report its `delay_min` and `source: live`

### Requirement: Curated interchange registry for cross-system transfers

Cross-system transfers between TRA and TRTC SHALL occur only at stations present in a curated interchange registry, each entry providing the TRA station id, the corresponding TRTC station id(s), and a `walk_min`. The system SHALL NOT infer cross-system station identity by name matching or geographic proximity.

#### Scenario: Transfer occurs at a registered interchange

- **WHEN** a journey changes between TRA and metro
- **THEN** the change SHALL be at a registry interchange, and the corresponding `transfers[]` entry SHALL carry that interchange's `walk_min`

#### Scenario: No registered interchange between modes

- **WHEN** a cross-mode journey has no registered interchange connecting the reachable TRA and metro sub-networks
- **THEN** the result SHALL be `{ routes: [], note }` rather than an error or a fabricated transfer

### Requirement: Endpoint disambiguation follows NSQL discipline

When `from` or `to` matches more than one station across the TRA and TRTC station sets, the tool SHALL return `{ matches: [...] }` listing the candidates for user disambiguation, and SHALL NOT guess a single endpoint or return a route.

#### Scenario: Ambiguous station name

- **WHEN** `from = 中山` matches stations in multiple systems
- **THEN** the result SHALL be `{ matches: [...] }` enumerating each candidate with enough detail (system, station id, name) to disambiguate, and SHALL NOT contain `legs`

### Requirement: Graceful degradation and empty-is-not-error

The tool SHALL treat "no route found" as a non-error result `{ routes: [], note }` and SHALL reserve errors for system-level failures (auth, network, rate limit). When the `DailyTrainTimetable` OD fetch fails or returns empty for a TRA-involving journey, the tool SHALL return `{ routes: [], note }` indicating the TRA timetable is temporarily unavailable, and SHALL NOT crash; metro-only journeys SHALL remain unaffected.

#### Scenario: TRA timetable temporarily unavailable

- **WHEN** the `DailyTrainTimetable` OD fetch returns HTTP 500 or empty for a TRA-involving journey
- **THEN** the result SHALL be `{ routes: [], note }` naming the timetable as temporarily unavailable, with no crash

#### Scenario: Unreachable origin/destination

- **WHEN** no path exists between `from` and `to` across the activated TRA + TRTC network
- **THEN** the result SHALL be `{ routes: [], note }` rather than an error
