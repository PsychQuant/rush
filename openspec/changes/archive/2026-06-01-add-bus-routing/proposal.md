## Why

Stage 3 of the (B) routing engine adds bus — Taiwan's densest, most-used mode. The first slice (3a) is **direct-route** within-city bus routing: given two stops, "which bus, coming when, arriving when". The existing `bus_find_routes` already intersects `StopOfRoute` to list candidate direct routes, but it carries **no timing** — no "next bus in N min", no arrival. `bus_route` adds the live timing that makes it a routing answer rather than a route list.

Probing real TDX shaped the design honestly: bus has **A2 `EstimatedTimeOfArrival`** (real-time per-stop ETA) — a genuine live signal metro lacks — but A2 is a **now-snapshot** ("next bus now", not "next bus at a future time T"), and there is **no static per-segment ride-time source** (`Bus/S2STravelTime` / `TravelTime` / `RouteTrafficTime` all 404). `Bus/Schedule` is mixed: most routes carry `Timetables` (departure phase), some only `Frequencys` (headway bands like metro). These constraints define the slice: live board-ETA is high-confidence; arrival is provided only where a timetable backs it, omitted (never faked) otherwise; transfers are deferred (a now-snapshot can't predict a future-time second boarding).

## What Changes

- New MCP tool `bus_route(from_stop, to_stop, city, depart_after?)` — direct-route within-city bus routing. Tool count 24 → 25.
- Candidate routes: intersect `StopOfRoute` for routes serving both stops with `from` before `to` in the same direction (reuse the `bus_find_routes` intersection logic).
- Per candidate route: **board** time from A2 live ETA at the origin stop (`source: live`), falling back to `Bus/Schedule` headway expected-wait (`source: frequency`) or next timetabled departure (`source: scheduled`); **arrival** at the destination stop from `Bus/Schedule` `Timetables` per-stop delta where the route is timetabled (`source: scheduled`), otherwise omitted with a note.
- New TDX endpoint wired: `Bus/Schedule/City/{city}` + a `BusSchedule` model (`Timetables` + `Frequencys`).
- Empty ≠ error: no direct route → `routes: [] + note` (transfers not yet supported).

## Non-Goals

- **Transfers / multi-leg bus journeys** — deferred to Stage 3b. A2's now-snapshot cannot predict a future-time second boarding, and with no static ride-time source, chaining legs is fragile.
- **Bus↔rail multi-modal** — Stage 3b (extends `transit_route` composition).
- **A ride-time estimation engine** (geo-distance / A2-differencing) — out of scope; arrival is timetable-backed or omitted, never estimated.
- **Cross-city routing** — single `city` per query.
- **Faked arrival precision** — frequency-only routes get a live board-ETA but no invented arrival time.
- **Extending or changing `bus_find_routes`** — its contract stays frozen; `bus_route` is a new tool.
- **Unified RAPTOR core** — deferred, possibly never (composition/reuse over a rewrite).

## Capabilities

### New Capabilities

- `bus-routing`: direct-route within-city bus routing with live A2 board-ETA and timetable-backed (or honestly-omitted) arrival, over the existing bus network datasets.

### Modified Capabilities

(none)

## Impact

- Affected specs: new capability `bus-routing`
- Affected code:
  - New: Sources/CheTransportMCP/Tools/BusRouter.swift, Tests/CheTransportMCPTests/BusRouterTests.swift, Tests/CheTransportMCPTests/BusRouteToolTests.swift, Tests/CheTransportMCPTests/BusRouteLiveTests.swift
  - Modified: Sources/CheTransportMCP/Tools/BusTools.swift, Sources/CheTransportMCP/Models/BusModels.swift, Sources/CheTransportMCP/TDXEndpoints.swift, Tests/CheTransportMCPTests/MCPJSONRPCSmokeTest.swift, CLAUDE.md, README.md, README_zh-TW.md, mcpb/manifest.json
  - Removed: (none)
