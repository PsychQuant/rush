# Design: bus→rail multimodal routing (Stage 3c-i)

## Context

`bus_rail_route` is the forward dual of `rail_bus_route` (3b): journey starts on a bus, ends on rail. It composes `BusRouter` (leg 1) + the `transit_route` engine / `MultimodalRouter` (leg 2) at a name-matched alight-hub — no RAPTOR core. A new sibling `BusRailRouter` holds the new logic so `RailBusRouter` and the three shipped tools stay frozen.

## Decision: forward discovery + bus-then-rail stitch

`bus_rail_route(from_stop, to, city, transfer?, depart_after?)`:

```
from_stop ──(bus routes serving it)──> scan DOWNSTREAM stops (index > from_stop)
          ──(name-match 捷運X站/X車站 → rail station)──> candidate alight-hubs
   for each hub:  bus(from_stop → hub stop, A2 LIVE)  then  rail(hub → to, departAfter = bus arrival + walk)
   pick earliest final RAIL arrival across hubs
```

Mirror of 3b-ii's reverse search, flipped: there the hub is *upstream* of `to_stop`; here it is *downstream* of `from_stop`.

## The timing chain (the honest wrinkle)

A2 gives a live **board** time, not an arrival. The bus arrival at the hub needs the timetable ride-time:

- Bus board: A2 live ETA at `from_stop` (`source: live`) → next timetabled departure (`scheduled`) → headway/2 (`frequency`). Boarding is NOW, so A2 is valid here (unlike 3b).
- Bus arrival at hub: timetable ride-time when the route is timetabled (`BusRouter` already returns `arrivalClockMin`), else unknown.
- Rail leg anchor: `departAfter = (bus arrival ?? bus board) + transferWalkMin`. When bus arrival is **unknown** (frequency-only bus, no ride-time), the anchor falls back to the board time and the result SHALL carry a note that the rail connection time is approximate — never silently presented as precise.

So the best case (A2-live board + timetabled ride) gives a fully-timed bus→rail journey; the frequency-only case still routes but discloses the approximation.

## In scope
`bus→rail` only; single transfer; TRA+TRTC rail leg (leg 2 via the `transit_route` engine); name-matched alight-hub (explicit or auto); A2-live leg-1 board; honest rail-anchor degradation + disclosure; NSQL disambiguation on `from_stop`/`to`; empty ≠ error; Asia/Taipei times.

## Out of scope
Multi-transfer; unified RAPTOR core; geo-proximity matching; non-TRA/TRTC rail; `bus→bus` transfers; changes to `rail_bus_route` / `transit_route` / `bus_route`.

## Interface points

- **New**: `Sources/CheTransportMCP/Tools/BusRailRouter.swift` — pure. `candidateAlightHubs(fromStopUID:routes:railStations:cap:) -> HubDiscovery` (downstream scan, name-match, dedup by (station, alight-stop), proximity order = closest downstream first, cap with dropped count); `compose(busOption:busBoardClockMin:hubStationName:transferWalkMin:railLegs:railArrMin:) -> Result`; `selectEarliest([Result]) -> Result?` (earliest rail arrival, known before unknown). Reuses `RailBusRouter.busStopMatchesStation` + `RailBusRouter.HubCandidate`/`HubDiscovery` types (no modification to RailBusRouter).
- **Modified**: `Sources/CheTransportMCP/Tools/TransitTools.swift` — register `bus_rail_route`; `executeBusRailRoute` with explicit + auto branches (resolve `from_stop` bus + `to` rail; fetch StopOfRoute/A2/schedule; per hub run bus leg `BusRouter.route` with A2 enabled then rail leg `MultimodalRouter.route(hub→to, departAfter=busArr+walk)`; compose; pick earliest). `MCPJSONRPCSmokeTest` 26→27.
- **Reused unchanged**: `BusRouter`, `MultimodalRouter`, `RailBusRouter` (name-match + types only), `transit_route`/`rail_bus_route`/`bus_route` (contracts frozen).

## Risks & mitigations
- **Bus arrival unknown breaks rail anchor** → fall back to board-time anchor + disclosed note (never faked). Covered by a frequency-only test.
- **Fan-out cost** (rail leg per hub) → cap (default reuse `RailBusRouter.maxAutoHubCandidates` = 8) + dedup; rail datasets cached.
- **No hub / `to` unreachable from any hub** → `routes:[] + note`.
- **Regression of 3b** → BusRailRouter is a new file; RailBusRouter only has its name-match + types *read*, not changed; explicit `rail_bus_route` tests stay green.

## Implementation Contract
- **Observable**: `bus_rail_route(from_stop, to, city, transfer?, depart_after?)` returns `legs[]` (one bus leg THEN rail legs, each with `mode` + `source`) + `transfers[]` (the alight-hub + `walk_min`, estimated) + `arrival_time` (rail leg arrival, or null+note when the rail leg can't be timed) + `duration_min` + `transfer_count`(=1). When `transfer` omitted: `auto_selected_transfer` names the chosen hub; candidate-cap overflow disclosed via `auto_hub_note`. Bus leg `source: live` when A2 present. Frequency-only bus leg (arrival unknown) → rail anchored at board-time + a note disclosing the approximation. No qualifying hub / `to` unreachable / no direct bus → `routes:[] + note`. Ambiguous `from_stop`/`to` → `matches`.
- **Interface**: tool `bus_rail_route(from_stop: string, to: string, city: string, transfer?: string, depart_after?: string)`; `from_stop`+`city` required, `to` required (rail station name/id); times Asia/Taipei. `BusRailRouter.candidateAlightHubs/compose/selectEarliest` pure.
- **Failure modes**: never errors on data gaps — missing hub / unreachable rail / no direct bus → empty+note; ambiguous endpoint → matches; cap truncation → note; bus-arrival-unknown → board-anchored rail + note.
- **Acceptance**: `BusRailRouterTests` (downstream-only discovery, district-name reject via reused name-match, dedup by (hub, alight stop), cap discloses dropped, proximity order closest-downstream-first, selectEarliest by rail arrival); `BusRailRouteToolTests` (explicit happy bus→rail with A2-live board; auto happy with auto_selected_transfer; ambiguous from_stop → matches; no-qualifying-hub → empty+note; frequency-only bus → rail board-anchored + note); `MCPJSONRPCSmokeTest` 26→27 with `bus_rail_route` present; existing tests green.
- **Scope boundary**: as In/Out scope. Multi-transfer + RAPTOR core excluded.
