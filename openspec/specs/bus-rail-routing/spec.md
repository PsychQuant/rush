# bus-rail-routing Specification

## Purpose

TBD - created by archiving change 'add-bus-rail-routing'. Update Purpose after archive.

## Requirements

### Requirement: Bus-to-rail multi-modal routing

The system SHALL provide a `bus_rail_route(from_stop, to, city, transfer?, depart_after?)` MCP tool that composes a bus leg (`from_stop` → an alight-hub) with a rail leg (the hub → `to`, via the TRA↔Taipei-Metro engine) within one `city`. `from_stop` SHALL be a bus stop; `to` SHALL be a rail station (TRA or TRTC); `transfer` SHALL be optional; `depart_after` defaults to now (Asia/Taipei). The bus leg boards at or after `depart_after` and, because boarding is at the journey start, the system SHALL use the live A2 ETA for the board when available (`source: live`), falling back to the next timetabled departure (`source: scheduled`) then headway/2 (`source: frequency`). The result SHALL contain `legs[]` (one bus leg THEN the rail legs, each with `mode` and `source`), `transfers[]` (the alight-hub with `walk_min`), `arrival_time`, `duration_min`, and `transfer_count`. All emitted times SHALL be Asia/Taipei (`+08:00`).

#### Scenario: Bus then rail to the destination

- **WHEN** a bus route serving `from_stop` has a downstream stop that name-matches a rail station from which `to` is reachable by rail
- **THEN** the result SHALL contain a bus leg from `from_stop` to the alight-hub stop, a transfer entry at the hub, and the rail legs from the hub to `to`, with the rail leg anchored at the bus arrival plus the transfer walk

#### Scenario: Live board on the first leg

- **WHEN** the live A2 ETA is available for a serving route at `from_stop`
- **THEN** the bus leg's board SHALL use it with `source: live`

#### Scenario: Rail leg unreachable

- **WHEN** no rail route exists from any candidate alight-hub to `to`
- **THEN** the result SHALL be `{ routes: [], note }`, not an error

##### Example: 公車站 → 捷運站轉乘 → 鐵路到目的地

- **GIVEN** `from_stop` a Taipei bus stop, `to = 南港` (rail), `depart_after` now
- **WHEN** `bus_rail_route` runs and a serving route reaches the `捷運市政府站` stop downstream
- **THEN** leg 1 is the bus from `from_stop` to `捷運市政府站` (`source: live` if A2 present), a transfer at 市政府 (`walk_min`), and leg 2 is the metro/TRA legs 市政府 → 南港, with `arrival_time` from the rail leg

---
### Requirement: Auto alight-hub selection when transfer omitted

When `transfer` is omitted, the system SHALL auto-select the alight-hub by a `from_stop`-anchored forward search: among the bus routes serving `from_stop`, for each route+direction it SHALL scan the stops downstream of `from_stop` (higher stop index, same direction) and name-match them to rail stations. Each match yields a candidate `(rail hub, alight stop)` pair; the system SHALL deduplicate by `(rail station, alight stop)`, route bus+rail per candidate, and return the itinerary with the earliest final rail arrival. The result SHALL include an `auto_selected_transfer` field naming the chosen hub. The candidate set SHALL be bounded by a cap; when the cap truncates candidates, the result SHALL carry a note disclosing how many were dropped. When `transfer` is provided, the system SHALL use that hub and SHALL NOT emit `auto_selected_transfer`.

#### Scenario: Auto-selected alight-hub

- **WHEN** `transfer` is omitted AND at least one bus route serving `from_stop` has a downstream stop name-matching a rail station from which `to` is reachable
- **THEN** the result SHALL contain the bus leg to the auto-selected hub, the rail legs to `to`, and `auto_selected_transfer` naming that hub, chosen as the earliest final rail arrival across candidates

#### Scenario: Candidate cap truncation is disclosed

- **WHEN** `transfer` is omitted AND the forward search finds more candidate hubs than the cap
- **THEN** the system SHALL keep the candidates closest downstream to `from_stop` up to the cap and the result SHALL carry a note stating how many were dropped

---
### Requirement: Honest bus-arrival timing for the rail anchor

When the bus leg is timetabled, the system SHALL anchor the rail leg at the bus arrival plus the transfer walk. When the bus leg's arrival time is unknown (a frequency-only route with no ride-time), the system SHALL anchor the rail leg at the bus board time plus the transfer walk and SHALL carry a note that the rail connection time is approximate. The system SHALL NOT present an approximated connection as precise.

#### Scenario: Frequency-only bus leg yields an approximate rail anchor

- **WHEN** the chosen bus route is frequency-only (no timetabled ride-time to the hub)
- **THEN** the rail leg SHALL be anchored at the bus board time plus the transfer walk AND the result SHALL carry a note that the connection time is approximate
