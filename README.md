# che-transport-mcp

A Model Context Protocol server providing real-time Taiwan transport queries via [TDX](https://tdx.transportdata.tw/).

[繁體中文 README](README_zh-TW.md) · [Design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md) · [v0.2 backlog](docs/v0.2-backlog.md)

## Status

**v0.2-dev** — 23 tools across all 7 transport modes (Rail / Bus / Bike / Air / Maritime / Traffic / Parking)

Roadmap:
- v0.1: Rail ✅ (5 tools)
- v0.2: Bus + Bike ✅ (8 tools)
- v0.3: Air + Maritime ✅ (5 tools)
- v0.4: Traffic + Parking ✅ (5 tools)
- v1.0: Release pipeline + marketplace

## Quick start

```bash
git clone <repo>
cd che-transport-mcp
make build
make setup-tdx   # interactive, prompts for TDX credentials
```

Register a free TDX account first at <https://tdx.transportdata.tw/register>.

## Tools

### Rail (5)

| Tool | Purpose |
|------|---------|
| `rail_list_systems` | List 8 supported rail systems (TRA / THSR / 4 metros / 2 light rails) |
| `rail_search_stations` | Fuzzy search station by name (parallel fan-out across systems) |
| `rail_find_trains` | Find trains by O/D + date (TRA / THSR) |
| `rail_status_train` | Live train status (delay, position) |
| `rail_status_station` | Live station board |

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

### Maritime (2)

| Tool | Purpose |
|------|---------|
| `maritime_list_routes` | Ferry route master, optional operator filter |
| `maritime_status_schedule` | Per-route schedule (raw TDX JSON pass-through) |

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

- **Read-only**: all 23 tools are GET-only against TDX. No execution risk.
- **Cache TTL tiers**: 24h static (stations / routes / lots / CCTV) · 1h timetables · 5-10 min news · 0s live (ETAs, positions, FIDS, parking availability).
- **Rate limit**: TDX free tier is 50/min. 429 triggers a single 1s retry.
- **Empty ≠ error**: empty result sets return normally; errors are system-level only.
- **Unified registry**: each transport mode appends tools into `ToolRegistry`; `Server.swift` installs one `ListTools` and one `CallTool` handler delegating to it. Adding a new mode is one `Tools/` file + one `Models/` file + one `register()` line.

See [design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md) for full architecture.

## License

MIT. See [LICENSE](LICENSE).
