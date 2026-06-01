# Design: Auto transfer-hub selection for rail→bus (Stage 3b-ii)

## Context

Stage 3b-i shipped `rail_bus_route(from, transfer, to_stop, city, depart_after?)` — rail to an **explicit** transfer station, then a name-matched bus leg. 3b-ii makes `transfer` optional and auto-selects the hub. The design constraint is to stay out of RAPTOR territory (defer-RAPTOR): no new engine, just a bounded discovery step feeding the existing 3b-i stitch.

## Decision: `to_stop`-anchored reverse search

The naïve forward search ("try every rail station reachable from `from`") is unbounded. Reverse it:

```
to_stop ──(bus routes serving it)──> for each route, walk UPSTREAM from to_stop
        ──(name-match each upstream stop to a rail station: 捷運X站 / X車站)──>
        candidate (rail hub, boarding stop) pairs                        ← small set
   for each candidate hub:  rail(from → hub)  +  bus(boarding → to_stop)  ← reuse 3b-i
   pick earliest final arrival across candidates
```

Only rail stations that a *direct bus to `to_stop`* passes through can be the transfer, so the candidate set is bounded by "name-matched upstream stops of `to_stop`'s serving routes" — typically a handful. This is the entire reason auto-hub is tractable without RAPTOR.

## In scope

- `rail_bus_route` with `transfer` **omitted** → auto-hub. With `transfer` present → frozen 3b-i path (unchanged).
- `rail→bus`, single transfer, TRA+TRTC rail leg, name-matched interchange.
- Earliest-arrival hub selection; bounded candidate cap with honest disclosure.
- Output identical to 3b-i + an `auto_selected_transfer` field naming the chosen hub.

## Out of scope

- `bus→rail`; multi-transfer; geo-proximity matching; non-TRA/TRTC rail; changes to the explicit-transfer path, `transit_route`, or `bus_route`.

## Reverse-search mechanics

1. Resolve `from` (rail) and `to_stop` (bus stop), same as 3b-i. `transfer` absent triggers auto-hub.
2. Fetch `to_stop`'s `city` StopOfRoute set; keep routes where `to_stop` appears. For each such route+direction, scan stops with index `< to_stop`'s index (upstream, same direction).
3. For each upstream stop, test `RailBusRouter.busStopMatchesStation(stopName:, stationName:)` against each candidate rail station name. A match yields a `(railStation, boardingStop, routeUID, direction)` candidate. (Rail station list = the resolvable TRA stations + TRTC station names already fetched for `from` resolution.)
4. Deduplicate candidates by `(rail station, boarding stopUID)`. Apply the cap (see below).
5. For each candidate hub: run the rail leg `from → hub` via `MultimodalRouter` (the 3b-i `composeRailLeg`), then the bus leg `boarding → to_stop` (A2 disabled, departAfter = railArrival + walk), then `RailBusRouter.compose`. Collect the stitched `Result`s.
6. Select the `Result` with the earliest `arrivalClockMin` (known arrivals before unknown, then soonest board) — the same ordering `compose` already uses for bus options, lifted to span hubs.

## Candidate cap (bound + honesty)

`RailBusRouter.maxAutoHubCandidates` (default 8). If reverse search finds more, keep the first N by upstream proximity to `to_stop` (closest boarding stops first = shortest bus ride) and set a `note` disclosing how many were dropped. Never silently truncate. Rationale: each candidate costs a rail-leg fetch+route; 8 bounds worst-case fan-out while covering realistic transfer choices.

## Interface points

- **New (pure)**: `RailBusRouter.candidateHubs(toStopUID:toStopIndexByRoute:routes:railStationNames:cap:) -> [HubCandidate]` — reverse search + name-match + dedup + cap. `HubCandidate { railStationName, railStationID, boardingStopUID, boardingStopName, routeUID, direction }`. Pure over already-fetched data; unit-testable without network.
- **New (pure)**: `RailBusRouter.selectEarliest(_ results: [Result]) -> Result?` — lift the existing earliest-arrival ordering to span candidate stitches.
- **Modified**: `TransitTools.executeRailBusRoute` — when `transfer` is nil, resolve rail station names, drive `candidateHubs`, loop the 3b-i compose per candidate, pick earliest, format (add `auto_selected_transfer`). When `transfer` is present, the existing path runs verbatim.
- **Modified**: tool schema — `transfer` moves out of `required`; description documents both modes.
- **Reused unchanged**: `MultimodalRouter`, `BusRouter`, `composeRailLeg`, `RailBusRouter.compose` / `busStopMatchesStation`.

## Risks & mitigations

- **Fan-out cost** (rail leg fetched per candidate) → cap at 8 + dedup; rail datasets are cached (24h static / 1h timetable / 0s live), so repeated rail-leg routing reuses fetches within a call.
- **No candidate found** (no serving bus route passes a name-matched rail station, or `from` can't reach any candidate hub) → `routes:[] + note`, never a guess.
- **Ambiguous which hub** → earliest-arrival is the deterministic tiebreak (North Star metric).
- **Regression of 3b-i** → explicit-transfer path is byte-for-byte unchanged; auto-hub is a separate branch gated on `transfer == nil`. Existing RailBusRouteToolTests stay green.
- **Cap hides a better hub beyond N** → ordering by upstream proximity puts the most plausible hubs first; the disclosure note tells the caller truncation happened.

## Implementation Contract

- **Observable**: `rail_bus_route(from, to_stop, city, depart_after?)` with `transfer` omitted returns the earliest-arrival rail→bus itinerary (`legs` = rail legs + one bus leg, `transfers`, `arrival_time` or null+note, `duration_min`, `transfer_count`=1) PLUS `auto_selected_transfer` = the chosen hub's station name. With `transfer` present, behavior is exactly 3b-i (no `auto_selected_transfer`). No qualifying hub / `from` cannot reach any hub → `routes:[] + note`. Ambiguous `from`/`to_stop` → `matches`. Candidate cap exceeded → result carries a disclosure note.
- **Interface**: `RailBusRouter.candidateHubs(...) -> [HubCandidate]` (pure, deduped, capped, proximity-ordered); `RailBusRouter.selectEarliest([Result]) -> Result?`; `RailBusRouter.maxAutoHubCandidates` constant (8). `transfer` optional in the tool schema.
- **Failure modes**: never errors on data gaps — missing hub, unreachable rail, no direct bus all degrade to `routes:[] + note`; ambiguous endpoints → `matches`; cap truncation → note (not silent).
- **Acceptance**: `RailBusRouterTests` (candidateHubs: upstream-only matches, district-name reject reused, dedup by (hub, boarding), cap truncation sets the dropped count, proximity ordering; selectEarliest picks min arrival across stitches); `RailBusRouteToolTests` (auto-hub happy path returns auto_selected_transfer + rail+bus legs; transfer-present path unchanged; no-qualifying-hub → empty+note; ambiguous to_stop → matches); `MCPJSONRPCSmokeTest` still 26 tools with `transfer` no longer required; existing 3b-i tests stay green.
- **Scope boundary**: as In/Out scope. `bus→rail`, multi-transfer, geo-matching excluded.
