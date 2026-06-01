# Design: Rail→Bus Multi-modal Routing (Stage 3b, first slice)

## Context

Stage 3b chains rail + bus. First slice = `rail→bus` with an **explicit transfer station** (auto-hub-selection deferred). It composes the existing routers — `MultimodalRouter` (rail leg, TRA↔TRTC) + `BusRouter` (bus leg) — at a name-matched bus↔rail interchange. No new routing engine (consistent with defer-RAPTOR).

Probed data realities that shape the design:
- **Name-matching, with structured patterns.** Bus stops at a rail station are named `捷運<X>站` (metro) or `<X>車站` / `<X>火車站` (TRA). Bare substring over-matches district names: `南港`→85 stops (most are `南港高工`/`南港軟體園區`, not the station), `松山`→57 (`松山機場` etc.). So match the **patterns**, not the bare name. Normalize `臺`↔`台` first (`台北車站`→0 hits vs `臺北車站`→20).
- **Transfer timing is honest, not live.** A2 is a now-snapshot — it cannot predict the future-time boarding after you arrive at the transfer. So the bus leg's board uses the 3a fallback chain WITHOUT A2: next timetabled departure ≥ (rail arrival + walk) → `source: scheduled`, else headway/2 → `source: frequency`. Final arrival = bus timetable arrival where timetabled, else omitted + note.

## Decision: compose `MultimodalRouter` + `BusRouter` at an explicit, name-matched transfer

`rail_bus_route(from, transfer, to_stop, city, depart_after?)`:

1. **Resolve** `from` + `transfer` to rail stations (reuse `transit_route`'s resolution; TRA+TRTC only), and `to_stop` to a bus stop (reuse `bus_route`'s resolution; ambiguous → `matches`).
2. **Rail leg**: `MultimodalRouter.route(from → transfer, departAfter)` → rail legs + arrival time at `transfer`. If unreachable → `{ routes: [], note }`.
3. **Interchange resolve**: among `city`'s bus stops, select those whose normalized name matches a pattern derived from the `transfer` station's name — `捷運<X>站`, `<X>車站`, `<X>火車站` (NOT bare `<X>`). These are the candidate boarding stops at the transfer.
4. **Bus leg**: for each candidate boarding stop, run the `BusRouter` direct-route logic to `to_stop` with `departAfterMin = railArrival + transferWalkMin` and **A2 disabled** (future-time board). Keep routes where a direct bus exists.
5. **Select + compose**: pick the candidate giving the earliest final arrival; assemble `legs[]` = rail legs + a `transfers[]` entry (at `transfer`, `walk_min`) + the bus leg. Output `arrival_time` (or null+note if the bus leg is frequency-only) + `duration_min` + `transfer_count`.

`transferWalkMin` is a constant estimate (default 5 min — the name-matched stop is at the station); documented as an estimate, not measured.

## Interchange name-matching (the crux)

Given the transfer station's display name `X` (normalized `臺`→`台`), a bus stop matches when its normalized name contains any of: `捷運` + `X` + `站`, or `X` + `車站`, or `X` + `火車站`. Worked examples from the probe: `市政府` → `捷運市政府站` ✓; `臺北` → `臺北車站(忠孝)` ✓ (via `X車站`); `南港` → `南港行政中心(南港車站)` ✓ (via `X車站`) while `南港高工` is correctly rejected (no pattern). This pattern-match is the only cross-mode-identity mechanism; it is bounded to the one explicit transfer station, so the all-Taiwan station-identity problem stays out of scope.

## Integration points

- **New**: `Sources/CheTransportMCP/Tools/RailBusRouter.swift` — pure composition: given the rail itinerary (from `MultimodalRouter`), the candidate boarding stops, and the per-candidate bus options (from `BusRouter`), stitch the earliest-arrival rail→walk→bus itinerary + the name-matching pattern helper (`busStopMatchesStation(stopName:stationName:)`).
- **Modified**: `Sources/CheTransportMCP/Tools/TransitTools.swift` — add the `rail_bus_route` Tool definition, dispatch case, and `executeRailBusRoute` (fetches both rail + bus datasets, drives `MultimodalRouter` + `BusRouter` + `RailBusRouter`). `MCPJSONRPCSmokeTest` 25→26 + `transit_`/tool counts. Docs + manifest.
- **Reused unchanged**: `MultimodalRouter`, `BusRouter`, `InterchangeRegistry`, `transit_route`/`bus_route` (their contracts stay frozen).

## In scope
`rail→bus` only; explicit `transfer` station; TRA+TRTC rail leg; name-matched interchange (pattern-based); honest bus-leg timing (schedule/headway, A2 disabled post-transfer); arrival timetabled-or-omitted; NSQL disambiguation on endpoints; empty ≠ error; Asia/Taipei times.

## Out of scope
Auto transfer-hub selection (3b-ii); `bus→rail`; multi-transfer; A2 live for the post-transfer bus leg; geo-proximity matching; non-TRA/TRTC rail; changes to `transit_route`/`bus_route`.

## Risks & mitigations
- **Name-match over/under-match** → structured patterns (`捷運X站`/`X車站`), normalized `臺`↔`台`; `RailBusRouterTests` cover a district-name station (南港: accept `南港車站`, reject `南港高工`).
- **Candidate stop not on a route to dest** → step 4 keeps only candidates with a direct bus route; if none → `{ routes: [], note }` (no rail→bus path at this transfer).
- **A2 misuse for future board** → A2 explicitly disabled in the bus leg; board from schedule/headway only. Stated.
- **transferWalk is an estimate** → labeled; not presented as measured.
- **Fetch volume** (rail + bus datasets in one call) → reuses existing cached fetches (24h static, 1h schedule, 0s live); acceptable.

## Implementation Contract
- **Observable**: `rail_bus_route(from, transfer, to_stop, city)` returns `legs[]` (rail legs with `source: live/scheduled` + one bus leg with `source: scheduled/frequency`) + `transfers[]` (the transfer station + `walk_min`) + `arrival_time` (or null+note for frequency-only bus) + `duration_min` + `transfer_count`. Rail unreachable / no name-matched stop with a route to dest → `{ routes: [], note }`. Ambiguous `to_stop`/`from`/`transfer` → `{ matches }`.
- **Interface**: tool `rail_bus_route(from: string, transfer: string, to_stop: string, city: string, depart_after?: string)`; `city` required; times Asia/Taipei.
- **Failure modes**: ambiguous endpoint → matches; rail leg unreachable → empty+note; no qualifying transfer bus stop → empty+note; bus schedule unavailable → board from headway, arrival omitted; never errors on data gaps.
- **Acceptance**: `RailBusRouterTests` (pure: name-match patterns incl. district-name reject; rail+bus stitch with board ≥ rail-arrival+walk; frequency-only bus → arrival null+note; earliest-arrival candidate selection); `RailBusRouteToolTests` (executor via fixtures: happy rail→bus, ambiguous to_stop → matches, rail-unreachable → empty+note, no-qualifying-stop → empty+note); `MCPJSONRPCSmokeTest` 25→26 + `rail_bus_route` present; existing tests stay green.
- **Scope boundary**: as In/Out scope.
