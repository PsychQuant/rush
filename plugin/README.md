# che-transport-mcp

[![Marketplace](https://img.shields.io/badge/marketplace-psychquant--claude--plugins-blue)](https://github.com/PsychQuant/psychquant-claude-plugins) [![Source](https://img.shields.io/badge/source-PsychQuant%2Fche--transport--mcp-blue)](https://github.com/PsychQuant/che-transport-mcp)

Claude Code plugin wrapping the `che-transport-mcp` Swift MCP server.
21 tools querying Taiwan's [TDX 運輸資料流通服務](https://tdx.transportdata.tw/) across **Rail / Bus / Bike / Air / Traffic / Parking**.

## Install

```
/plugin marketplace add PsychQuant/psychquant-claude-plugins
/plugin install che-transport-mcp@psychquant-claude-plugins
```

The wrapper auto-downloads the signed + notarized `CheTransportMCP` binary from the corresponding GitHub Release on first MCP spawn (atomic swap, sha256-verifiable).

## Setup (one-time, ~3 min)

1. Register a free TDX account: <https://tdx.transportdata.tw/register>
2. From the TDX 會員中心 → API 金鑰, create an API key (you get `client_id` + `client_secret`)
3. Seed the macOS keychain:

```
/che-transport-mcp:setup-tdx
```

The skill opens a **real Terminal window** running `CheTransportMCP --setup` — a subcommand of the signed binary that prompts for `client_id` / `client_secret` (the secret hidden via `getpass`), writes them to keychain service `che-transport-tdx`, and verifies with a live OAuth round-trip. The secret is typed into that separate window, so it never appears in Claude Code's transcript.

4. **Quit Claude Code fully** (Cmd+Q) and reopen so the MCP server picks up the new credentials.

## What you can ask

| Example user query | Tools that fire |
|--------------------|-----------------|
| 下一班高鐵台北到左營 | `rail_search_stations` → `rail_find_trains` |
| 台北車站附近 YouBike | `bike_stations_nearby` |
| 307 公車到站時間 | `bus_search_stops` → `bus_status_arrivals` |
| 桃園機場 BR189 班機狀態 | `air_status_flights` |
| 國道 1 號現在塞嗎 | `traffic_freeway_live` |
| 信義區停車場 | `parking_list_lots` → `parking_status` |

## Components

- **MCP server**: `transport` (auto-spawned via `.mcp.json` + wrapper)
- **Skills**: `/che-transport-mcp:setup-tdx`, `/che-transport-mcp:today-rail`, `/che-transport-mcp:nearby-bike`
- **Hooks**: `SessionStart` — single-line banner with binary version + TDX credential status

## Architecture

See [CLAUDE.md](./CLAUDE.md) for invariants the LLM should respect:

- Time zone Asia/Taipei
- Empty ≠ error
- City required for Bus / Parking
- NSQL parse-confirm-call discipline for ambiguous queries

## Update

Plugin shell changes (skills, wrapper, hooks):
```
/plugin-tools:plugin-update che-transport-mcp
```

Binary upgrade — bump `version` in `.claude-plugin/plugin.json`; wrapper detects drift via the `~/bin/.CheTransportMCP.version` sidecar and re-downloads on next spawn.

## License

MIT. See [LICENSE](https://github.com/PsychQuant/che-transport-mcp/blob/main/LICENSE) in the binary source repo.
