# rush

A Model Context Protocol server providing real-time Taiwan transport queries via [TDX](https://tdx.transportdata.tw/).

[繁體中文 README](README_zh-TW.md) · [Design spec](docs/superpowers/specs/2026-05-20-rush-design.md) · [v0.2 backlog](docs/v0.2-backlog.md)

## Status

**v0.2-dev** — 27 tools across 6 transport modes (Rail / Bus / Bike / Air / Traffic / Parking) incl. `transit_route` (TRA↔Taipei-Metro multi-modal), `bus_route` (direct-route bus, live A2 board ETA), `rail_bus_route` (rail→bus; explicit or auto-selected hub) + `bus_rail_route` (bus→rail; A2-live first leg, explicit or auto-selected hub)

Roadmap:
- v0.1: Rail ✅ (5 tools)
- v0.2: Bus + Bike ✅ (8 tools)
- v0.3: Air ✅ (3 tools; maritime dropped — TDX has no callable maritime API, see #4)
- v0.4: Traffic + Parking ✅ (5 tools)
- v1.0: Release pipeline + marketplace

## Quick start

```bash
git clone <repo>
cd rush
make build
make setup-tdx   # interactive, prompts for TDX credentials
```

Register a free TDX account first at <https://tdx.transportdata.tw/register>.

## Tools

### Rail (7)

| Tool | Purpose |
|------|---------|
| `rail_list_systems` | List 8 supported rail systems (TRA / THSR / 4 metros / 2 light rails) |
| `rail_search_stations` | Fuzzy search station by name (parallel fan-out across systems) |
| `rail_find_trains` | Find trains by O/D + date (TRA / THSR) |
| `rail_status_train` | Live train status (delay, position) |
| `rail_status_station` | Live station board |
| `metro_find_route` | Metro O/D routing incl. cross-line transfers — shortest path over the station network as `legs[]` (per line ridden) + `transfers[]` (per line change, with walk + estimated wait) + `transfer_count` + total travel time (direct = 0-transfer path) |
| `rail_route` | TRA time-dependent O/D routing — real-timetable earliest arrival, live-adjusted for delays (legs + arrival_time + duration); TRA only |

### Bus (5)

| Tool | Purpose |
|------|---------|
| `bus_search_routes` | Fuzzy route search within a city |
| `bus_search_stops` | Fuzzy stop search within a city |
| `bus_find_routes` | O/D intersection — routes that visit both stops |
| `bus_status_arrivals` | ETA at a stop |
| `bus_status_positions` | Live bus positions on a route |

City is **required** for all Bus tools — 22 BusCity codes (`Taipei`, `NewTaipei`, …, `LienchiangCounty`).

### Bike (3) — YouBike 1.0 + 2.0

| Tool | Purpose |
|------|---------|
| `bike_search_stations` | Station search by name; optional service_type filter |
| `bike_stations_nearby` | Haversine-based nearby search + live availability |
| `bike_status_station` | Live rent/return count for a single station |

### Air (3)

| Tool | Purpose |
|------|---------|
| `air_list_airports` | Taiwan airport master |
| `air_find_flights` | Schedule lookup by airport + Arrival/Departure |
| `air_status_flights` | Live FIDS board |

### Traffic (3)

| Tool | Purpose |
|------|---------|
| `traffic_freeway_live` | Freeway section live speed / congestion |
| `traffic_incidents` | News feed (5-min cache) with keyword filter |
| `traffic_cctv` | CCTV stream URL inventory |

### Parking (2)

| Tool | Purpose |
|------|---------|
| `parking_list_lots` | Off-street car park master per city |
| `parking_status` | Live available-spaces lookup |

## Architecture

- **Read-only**: all 27 tools are GET-only against TDX. No execution risk.
- **Cache TTL tiers**: 24h static (stations / routes / lots / CCTV) · 1h timetables · 5-10 min news · 0s live (ETAs, positions, FIDS, parking availability).
- **Rate limit**: TDX free tier is 50/min. 429 triggers a single 1s retry.
- **Empty ≠ error**: empty result sets return normally; errors are system-level only.
- **Unified registry**: each transport mode appends tools into `ToolRegistry`; `Server.swift` installs one `ListTools` and one `CallTool` handler delegating to it. Adding a new mode is one `Tools/` file + one `Models/` file + one `register()` line.

See [design spec](docs/superpowers/specs/2026-05-20-rush-design.md) for full architecture.

## License

MIT. See [LICENSE](LICENSE).

## Migration from che-transport-mcp

Rush was previously distributed as `che-transport-mcp`. The plugin name changed, so Claude Code treats `rush` as a **new** plugin — existing installs do not auto-upgrade across the rename.

To migrate:
1. Uninstall the old plugin: `/plugin uninstall che-transport-mcp`
2. Install Rush from its self-marketplace (this repo) or the central marketplace: `/plugin install rush@<marketplace>`

Your TDX credentials carry over unchanged — they live under the keychain service `che-transport-tdx`, preserved across the rebrand, so **no re-setup is needed**. The GitHub repository was renamed (`PsychQuant/che-transport-mcp` → `PsychQuant/rush`); GitHub redirects old URLs.
