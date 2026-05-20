# CLAUDE.md — che-transport-mcp

This file is read by LLM agents (Claude Code, Codex, etc.) that use this MCP server. Follow these conventions to avoid common pitfalls.

## What this MCP does

Provides 23 tools over the [TDX 運輸資料流通服務](https://tdx.transportdata.tw/) covering 7 transport modes in Taiwan: Rail (TRA / THSR / 各捷運與輕軌), Bus, Bike (YouBike), Air, Maritime, Traffic, Parking.

This Plan 1 build covers **Rail only** (5 tools). Other modes ship in Plans 2-4.

## Interaction discipline — NSQL

Reference: <https://github.com/kiki830621/NSQL>

This MCP is read-only (no execution risk), but **input ambiguity is frequent**. Examples:

- 「中山」站 → 紅線？淡水線？桃捷？台中？
- 「下一班」→ 時間錨點為何？
- 「往台北」→ 起站為何？

Before calling any tool, **follow NSQL confirmation protocol**:

1. Parse user query into `function + arguments`
2. Render parsed form back to user
3. Wait for confirmation
4. Then call the tool

### Example dialogue

> User: 「下一班高鐵」
>
> Claude: 「我理解你要查 (起站) → (迄站) 從 (現在時間) 起的下一班高鐵。請問起迄站？」
>
> User: 「台北到左營」
>
> Claude: 「即將呼叫 `rail_find_trains(from='1000', to='1070', system='THSR', date='2026-05-20')`。確認嗎？」
>
> User: 對 → Claude 呼叫 tool

### Common ambiguity hotspots

| Query phrase | Ambiguity | Resolution |
|--------------|-----------|------------|
| 「中山」「忠孝」站 | 多 system 同名 | 先 `rail_search_stations(query)`，回多筆讓 user 選 |
| 「下一班」「最近」 | 時間錨點 | Default = now (Asia/Taipei)；若 user 指其他時間需明說 |
| 「往北」「往南」 | 方向 vs 起迄站 | TDX 用 O/D 而非方向；必須轉成兩個 station_id |
| 「自強號」「對號」 | 車種篩選 | TDX 回應已含車種；client 端在 result 內 filter |

## Setup

```bash
make setup-tdx   # one-time, interactive
```

This script prompts for TDX `client_id` / `client_secret`（at <https://tdx.transportdata.tw/register>）and stores them in macOS keychain under service `che-transport-tdx`.

## Tools (Plan 1 — Rail)

- `rail_list_systems()` — 列出 8 個支援 system
- `rail_search_stations(query, system?)` — 模糊搜尋站點 → station_id
- `rail_find_trains(from, to, date, system)` — O/D 找班次
- `rail_status_train(train_no, system)` — 特定列車即時誤點
- `rail_status_station(station_id, system)` — 站到站板（即時）

See `docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md` for full design.

## Architecture invariants

- **Time zone**: All time strings emitted by tools are in Asia/Taipei (`+08:00`)
- **Empty ≠ error**: Tools return `{ "matches": [] }` or `{ "trains": [] }` when no data found. Errors are reserved for system-level issues (auth, network, rate limit)
- **Cache TTL**: 24h static / 1h timetable / 0s live
- **Rate limit**: TDX free tier = 50/min. 429 triggers single retry; second 429 returns error

## Development

```bash
swift build              # build
swift test               # all tests (integration skips if no keychain)
make check-auth          # verify TDX creds work
swift run CheTransportMCP --version
```
