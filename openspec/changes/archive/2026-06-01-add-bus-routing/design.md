# Design: Direct-route Bus Routing (Stage 3a)

## Context

Stage 3a adds `bus_route` — direct-route within-city bus routing — the first bus slice of the (B) engine. `bus_find_routes` already intersects `StopOfRoute` to list candidate direct routes but carries no timing. `bus_route` adds live board-ETA + (timetable-backed) arrival.

Real TDX data (probed) defines the model:
- **A2 `EstimatedTimeOfArrival`** — real-time per-`(RouteID, Direction, StopID)` ETA (`EstimateTime` seconds; null when no live bus). A **now-snapshot** ("next bus now"), not a future-time query.
- **`Bus/Schedule`** — mixed: `Timetables` (per-trip `StopTimes` with per-stop `ArrivalTime`/`DepartureTime`) for most routes; `Frequencys` (headway bands per `ServiceDay`) for the rest.
- **No static per-segment ride-time** (`Bus/S2STravelTime` / `TravelTime` / `RouteTrafficTime` all 404). Ride-time comes only from `Timetables` deltas.

## Decision: compose existing pieces; no graph, no transfers

`bus_route` reuses the `bus_find_routes` `StopOfRoute` intersection + the A2 read path (`bus_status_arrivals`), adds a new `Bus/Schedule` fetch, and a pure `BusRouter` that assembles per-route board/arrival. No new graph engine (consistent with the defer-RAPTOR decision). Transfers deferred to 3b because A2's now-snapshot can't time a future second boarding and there is no ride-time source to chain.

## Algorithm (per query)

1. **Resolve** `from_stop` / `to_stop` to stop IDs within `city` (reuse bus stop search). Ambiguous name → `{ matches }` (NSQL), no route.
2. **Candidate direct routes**: from `Bus/StopOfRoute/City/{city}`, keep routes (sub-route aware) whose ordered `Stops` contain both the origin and destination stop with `origin StopSequence < dest StopSequence` in the same `Direction`. (This is the `bus_find_routes` intersection, extended to keep sequence + direction.)
3. **Live board-ETA**: fetch `Bus/EstimatedTimeOfArrival/City/{city}` filtered to the origin stop (OData `$filter=StopID eq '<id>'` to bound the response — the city-wide feed is large). For each candidate `(route, direction)`, the matching A2 record's `EstimateTime` (seconds → minutes) is the live board wait. `source: live`.
4. **Schedule fetch**: `Bus/Schedule/City/{city}`. For each candidate route+direction:
   - **Ride-time** (timetabled routes): pick the trip whose origin-stop `DepartureTime` is the earliest `>= depart_after`; ride-time = that trip's dest-stop `ArrivalTime` − origin-stop `DepartureTime`. Arrival = board + ride-time, `source: scheduled`.
   - **Board fallback** (no A2 live): timetabled → next trip's origin `DepartureTime` (`source: scheduled`); frequency-only → `MinHeadwayMins(band@now)/2` expected-wait (`source: frequency`).
   - **Frequency-only routes**: arrival **omitted** (`arrival_time: null`) with a per-route note — no per-stop times means no honest ride-time.
5. **Assemble + sort**: `routes[]`, each `{ route_name, sub_route_name?, direction, board_stop, board_in_min, board_source, alight_stop, arrival_time, arrival_source }`. Sort by earliest arrival when known, else soonest board. No direct route → `{ routes: [], note }` (transfers not yet supported).

## Data model + endpoint

- New endpoint `busSchedule(city) = v2/Bus/Schedule/City/{city}`; contract case added.
- New `BusSchedule` model: `{ routeID, routeName, subRouteID?, direction, frequencys: [BusFrequency], timetables: [BusTimetable] }`; `BusFrequency { startTime, endTime, minHeadwayMins, maxHeadwayMins, serviceDay }`; `BusTimetable { tripID, serviceDay, stopTimes: [BusScheduleStopTime] }`; `BusScheduleStopTime { stopSequence, stopID, arrivalTime, departureTime }`; `BusServiceDay` (weekday Int flags 0/1). Decoded bare-or-wrapped via `TDXDecode.list`.
- Reuse `BusStopOfRoute`/`BusStopOfRouteStop` (sequence + direction), `BusArrival` (`estimateTime`), bus stop search.

## In scope
Direct routes only; one `city`; live board-ETA (A2) with headway/timetable fallback; timetable-backed arrival or honest omission; NSQL stop disambiguation; empty ≠ error; Asia/Taipei times.

## Out of scope
Transfers / multi-leg (3b); bus↔rail multimodal (3b); ride-time estimation engine; cross-city; faked arrival for frequency routes; changes to `bus_find_routes`; unified RAPTOR core.

## Risks & mitigations
- **A2 now-snapshot** → only powers the origin board-ETA, never downstream legs (transfers excluded). Stated.
- **A2 city feed volume** → `$filter=StopID eq` bounds the response to the origin stop; mitigated.
- **Sub-route complexity** (`StopOfRoute` splits a route into sub-routes/variants) → match by sub-route + direction + stop sequence, as `bus_find_routes` already does; `BusRouterTests` cover a 2-sub-route case.
- **Frequency-only arrival** → omitted + noted, not estimated (honest data ceiling).
- **Live verification needs healthy TDX + service hours** → offline tests use fixtures; live check via env-cred gated test (the Stage 2 pattern), may show `frequency`/omitted arrival off-hours.

## Implementation Contract
- **Observable**: `bus_route(from_stop, to_stop, city)` returns `routes[]` of direct routes serving both stops, each with a live `board_in_min` (when A2 has it) + `arrival_time` (when timetabled) or `arrival_time: null` + note (frequency-only); no direct route → `{ routes: [], note }`; ambiguous stop → `{ matches }`.
- **Interface**: tool `bus_route(from_stop: string, to_stop: string, city: string, depart_after?: string)`; `city` required (BusCity code); times Asia/Taipei.
- **Failure modes**: ambiguous stop → matches; no direct route → empty + note; A2 unavailable → board falls back to schedule/headway (never errors); schedule unavailable → board still from A2, arrival omitted.
- **Acceptance**: `BusRouterTests` (pure: timetabled route → board+arrival with ride-time delta; frequency route → board only, arrival null+note; A2-live preferred over schedule fallback; direction/sequence filtering; sub-route case); `BusRouteToolTests` (executor via fixtures: happy path, ambiguous stop → matches, no-direct-route → empty+note, A2-missing graceful); `MCPJSONRPCSmokeTest` tool count 24→25 + `bus_` prefix 5→6; existing bus tests stay green.
- **Scope boundary**: as In/Out scope above.
