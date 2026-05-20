# che-transport-mcp

A Model Context Protocol server providing real-time Taiwan transport queries via [TDX](https://tdx.transportdata.tw/).

[繁體中文 README](README_zh-TW.md) · [Design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md)

## Status

**v0.1.0** — Rail tools only (TRA / THSR / 4 metros / 2 light rails)

Roadmap:
- v0.1: Rail (this release) ✅
- v0.2: Bus + Bike
- v0.3: Air + Maritime
- v0.4: Traffic + Parking
- v1.0: Release pipeline + marketplace

## Quick start

```bash
git clone <repo>
cd che-transport-mcp
make build
make setup-tdx   # interactive, prompts for TDX credentials
```

Register a free TDX account first at <https://tdx.transportdata.tw/register>.

## Tools (Plan 1)

| Tool | Purpose |
|------|---------|
| `rail_list_systems` | List 8 supported rail systems |
| `rail_search_stations` | Fuzzy search station by name |
| `rail_find_trains` | Find trains by O/D + date |
| `rail_status_train` | Live train status (delay, position) |
| `rail_status_station` | Live station board |

## Architecture

See [design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md).

## License

MIT. See [LICENSE](LICENSE).
