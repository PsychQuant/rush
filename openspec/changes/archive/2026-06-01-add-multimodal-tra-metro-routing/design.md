# Design: Multi-modal TRA↔Taipei-Metro Routing (Stage 2)

## Context

Stage 1 (`rail_route`, v0.6.0) gave TRA time-dependent earliest-arrival via `TimetableRouter` (connection-scan over `DailyTrainTimetable` + `TrainLiveBoard` live delay). `metro_find_route` (v0.5.0) gives structural metro O/D with `headway/2` wait. Neither can route a journey that crosses modes. This stage adds `transit_route` for TRA↔Taipei-Metro (TRTC), scoped to a curated interchange registry, and builds the unified time-dependent search that Stage 3 (full multi-modal + bus) will extend.

## Decision: time-anchored multi-leg composition over interchanges

A new `MultimodalRouter` composes a journey from at most one mode crossing at a curated interchange, **reusing both existing routers unchanged**:

- **TRA legs** → `TimetableRouter.earliestArrival` (the Stage 1 CSA, with `TrainLiveBoard` live delay already folded in). `source: live`.
- **Metro legs** → `MetroGraph.shortestPathByTime`, with the graph built using the headway band active at the moment the traveller enters the metro (so wait reflects peak/off-peak). `source: frequency`.
- **The seam** → the interchange registry supplies the transfer station pairing + `walk_min`.

The router enumerates the relevant interchanges, composes `[TRA sub-journey to interchange] + [walk] + [metro sub-journey to destination]` (and the mirror, metro-first), adds the expected first-boarding wait when entering metro, and selects the composition with the earliest destination arrival. Same-system journeys (TRA-only / metro-only) delegate directly to the corresponding router.

### Why composition, not a unified time-dependent Dijkstra (revised during apply)

The original design chose a unified time-dependent Dijkstra over a TRA∪metro graph. Reading the code during apply changed the call:

- `MetroGraph` is **already** a Dijkstra graph that bakes `headway/2` boarding wait into static edge costs (ride edges = travel time; transfer edges = walk + dest-line `headway/2`). A unified time-dependent Dijkstra would either **duplicate that entire edge-building** (directly against the #3 DRY work just shipped) or require a **risky refactor of `MetroGraph`** that endangers the working `metro_find_route`.
- The unified search's only real advantages over composition — arbitrary mode interleaving and mid-metro band-crossing — are **marginal for TRA↔TRTC** (metro legs are short; real journeys cross modes once). Its claimed Stage-3-substrate value is also weak: Stage 3 (bus + more metros + full live feed) will rewrite the routing core regardless.
- **Composition reuses both routers as-is** (zero duplication, no risk to `metro_find_route`), keeps TRA legs on the validated live-delay CSA and metro legs on the validated `MetroGraph` cost model, and delivers the identical user-facing itinerary.

Rejected alternatives:
- **Unified time-dependent Dijkstra**: duplication / `MetroGraph` refactor risk for marginal benefit (above).
- **CSA extension** (materialize metro as fixed-departure connections): metro has frequency + time-bands but no phase, so synthesized departures would be fabricated.

### Composition algorithm

1. **Resolve** `from`/`to` to `(system, stationID)` across TRA + TRTC (NSQL: ambiguous → `matches[]`).
2. **Same system** → delegate (`TimetableRouter` for TRA, `MetroGraph` for metro at band@`depart_after`).
3. **TRA → metro**: for each registry interchange `I` whose TRA side is reachable —
   - `t_I` = `TimetableRouter.earliestArrival(origin → I.traStationID, departAfter)` arrival (TRA legs captured).
   - `t_board` = `t_I + I.walkMin`.
   - For each `I.trtcStationID`: metro path to `dest` via `MetroGraph.shortestPathByTime`, graph built with `headwayByLine(band@t_board)`; add the entry-line **first-boarding wait** `headway(entryLine, band@t_board)/2` to `t_board` (MetroGraph adds wait only at line-transfer edges, not at first boarding).
   - arrival = `t_board + entryWait + metroPath.totalMinutes`.
   - Keep the `(I, trtc node)` minimizing arrival.
4. **metro → TRA**: mirror — metro from origin (band@`departAfter`, incl. first-boarding wait) to `I.trtcStationID`, `+ walkMin`, then `TimetableRouter.earliestArrival(I.traStationID → dest, t_after_walk)`.
5. **Assemble** `legs[]` (TRA legs from the itinerary, metro legs from the path's ride runs merged per line), `transfers[]` (the interchange + `walkMin`), `arrival_time`, `duration_min`, `transfer_count`. Out-of-scope: multi-crossing (TRA→metro→TRA) — single crossing only.

### Node graph / edge cost

There is no single unified graph: TRA uses `TimetableRouter`'s connection set (per-stop-pair, live-adjusted); metro uses `MetroGraph`'s adjacency (ride + line-transfer edges); the interchange registry is the only cross-mode link. Each router keeps its own cost model.

### depart_after anchor

`depart_after` default = now (Asia/Taipei). Origin label = `depart_after` (parsed `HH:mm`; out-of-range/garbage → validation error, reusing the bounded `minutesOfDay` guard from Stage 1).

### from/to resolution (NSQL discipline)

`from`/`to` accept a query string resolved across the TRA + TRTC station sets. Unique match → use it. Ambiguous (same name in multiple systems, e.g. 中山) → return `{ "matches": [...] }` for user disambiguation (empty ≠ error; no guessing) instead of a route.

## Interchange registry

`InterchangeRegistry.swift`: a hardcoded table of entries `{ name, tra_station_id, trtc_station_ids: [..], walk_min }`. v1 entries are the real TRA↔TRTC interchanges: 台北車站, 板橋, 南港, 松山. **Station IDs MUST be probed from live TDX before finalizing** (see Risks + the probe task) — per the #4/#5 probe-before-design lesson.

## Tool: transit_route

- **Signature**: `transit_route(from: string, to: string, depart_after?: string)`.
- **Output**: `{ legs: [{ mode: "TRA"|"Metro", line_or_train, from_station, to_station, dep_time, arr_time, delay_min?, source: "live"|"scheduled"|"frequency" }], transfers: [{ at, walk_min }], arrival_time, duration_min, transfer_count }`; or `{ matches: [...] }` on an ambiguous endpoint; or `{ routes: [], note }` when unreachable or data unavailable.
- All times Asia/Taipei (+08:00). Empty ≠ error.

## Integration points

- **New**: `Sources/CheTransportMCP/Tools/MultimodalRouter.swift` (the search), `Sources/CheTransportMCP/Tools/InterchangeRegistry.swift` (the registry), `Sources/CheTransportMCP/Tools/TransitTools.swift` (`register` + `defineTools` + `handleCall` + `executeRoute`).
- **Reused unchanged**: `TimetableRouter` (TRA CSA + live delay, `earliestArrival`/`clock`/`minutesOfDay`) and `MetroGraph` (metro Dijkstra). `MultimodalRouter` calls both; neither is modified, so `rail_route` and `metro_find_route` stay byte-for-byte identical (guarded by their existing tests). A small visibility tweak (making the relevant `TimetableRouter`/`MetroGraph` members reachable from `MultimodalRouter` within the module) is the only change to existing routers.
- **Modified**: `Sources/CheTransportMCP/Server.swift` — add `TransitTools.register`. `CLAUDE.md`, `README.md`, `README_zh-TW.md`, `mcpb/manifest.json` — document the new tool, tool count 23 → 24.

## In scope

TRA + TRTC; curated interchanges; single-criterion earliest-arrival; expected-wait metro legs; live-delay-adjusted TRA legs; `depart_after` anchor; NSQL endpoint disambiguation; graceful degradation (timetable 500/empty → `routes:[] + note`, never crash).

## Out of scope

Bus, ferry, non-TRTC metro systems; THSR (deferred — TRA+TRTC only for v1); multi-criteria optimization (transfers-vs-time); per-vehicle metro live data (no metro `source: live`); fare; algorithmic cross-system station identity (only the curated registry); Stage 3 full unified CSA + full live feed.

## Risks & mitigations

- **Metro wait correctness** (entry-band selection, expected-wait `headway/2`, first-boarding wait) → `MultimodalRouterTests` with synthetic headway bands. Mid-metro band-crossing is out of scope (band fixed at metro-entry time — metro legs are short); stated explicitly.
- **Interchange registry station IDs wrong** → probe live TDX (dedicated task) + `InterchangeRegistryTests` sanity check (IDs non-empty, `walk_min` in a plausible range).
- **`DailyTrainTimetable` OD transient HTTP 500** (the lone contract red across releases) → graceful: a TRA-involving route that can't fetch the timetable returns `routes:[] + note "TRA timetable temporarily unavailable"`, never crashes; metro-only journeys are unaffected.
- **Live verification needs TDX healthy** → offline tests use fixtures; live `transit_route(中壢→西門)` check deferred to apply time, may wait for TDX recovery.
- **Scope creep into full unified CSA** → bounded by curated registry + TRA+TRTC-only node activation.

## Implementation Contract

- **Observable behavior**: `transit_route(from=中壢, to=西門, depart_after=08:00)` returns a 2-leg itinerary — TRA 中壢→台北車站 (`source: live`, `delay_min`), transfer at 台北車站 (`walk_min`), Metro 板南線 台北車站→西門 (`source: frequency`) — with `arrival_time`, `duration_min`, `transfer_count: 1`.
- **Interface/data shape**: tool name `transit_route`; output shape as defined above; times +08:00; empty ≠ error.
- **Failure modes**: ambiguous endpoint → `{matches:[...]}`; unreachable O/D → `{routes:[], note}`; TRA timetable down → `{routes:[], note}` (no crash); missing metro data → `note`.
- **Acceptance**: `TransitToolsTests` (executor: multimodal happy path via fixtures, ambiguous-endpoint disambiguation, TRA-timetable-unavailable graceful degradation, metro-only journey); `MultimodalRouterTests` (earliest-arrival over the mixed graph, frequency expected-wait, band-crossing, interchange transfer); `InterchangeRegistryTests`; existing `TimetableRouterTests` + `rail_route` stay green (no behavior change); `MCPJSONRPCSmokeTest` tool count 23 → 24.
- **Scope boundary**: as In scope / Out of scope above.
