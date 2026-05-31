<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

# CLAUDE.md — che-transport-mcp

This file is read by LLM agents (Claude Code, Codex, etc.) that use this MCP server. Follow these conventions to avoid common pitfalls.

## What this MCP does

Provides 22 tools over the [TDX 運輸資料流通服務](https://tdx.transportdata.tw/) covering 6 transport modes in Taiwan: Rail (TRA / THSR / 各捷運與輕軌), Bus, Bike (YouBike), Air, Traffic, Parking.

Current build covers **all 22 tools across 6 modes**. Per-module tool catalogue below.

> **Maritime (航運/渡輪) is not covered.** TDX no longer serves it on the unified API (every `v2`/`v3` `Maritime`/`Ship` path 404s) and the legacy PTX `Ship` API is decommissioned (403 regardless of auth). The contract suite confirmed there is no callable maritime endpoint, so those tools were removed rather than ship broken. See PsychQuant/che-transport-mcp#4.

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
make setup-tdx                 # one-time, interactive (wraps CheTransportMCP --setup)
# or directly, once the binary is built/installed:
CheTransportMCP --setup
```

`--setup` prompts for TDX `client_id` / `client_secret`（register at <https://tdx.transportdata.tw/register>），writes them to the macOS keychain under service `che-transport-tdx`, and verifies with a live OAuth round-trip. The secret prompt uses `getpass` so it never echoes.

## Tools (22 total across 6 modes)

### Rail (6)
- `rail_list_systems()` — 列出 8 個支援 system
- `rail_search_stations(query, system?)` — 模糊搜尋站點 → station_id（未指定 system 會並行 fan-out）
- `rail_find_trains(from, to, date, system)` — O/D 找班次（僅 TRA / THSR）
- `rail_status_train(train_no, system)` — 特定列車即時誤點
- `rail_status_station(station_id, system)` — 站到站板（即時）
  - Note: `window_min` 參數在 schema 中接受（forward-compatibility），但目前 **未生效** — TDX `StationLiveBoard` endpoint 自帶預設視窗。Client-side 視窗過濾預計 v0.3 加入。
- `metro_find_route(from, to, system)` — 捷運 O/D 路線（含跨線轉乘）：建站網圖跑最短路徑，回 routes[]，每條含 legs（每段線+時間+班距）+ transfers（換乘站+步行+估計等車）+ transfer_count + 總時間。直達 = 0 transfer。

### Bus (5) — city 必填
- `bus_search_routes(query, city)` — 路線模糊搜尋
- `bus_search_stops(query, city)` — 站牌模糊搜尋
- `bus_find_routes(from_stop, to_stop, city)` — O/D 候選路線（從 `StopOfRoute` 交集）
- `bus_status_arrivals(stop_id, city)` — 站牌即時到站預估
- `bus_status_positions(route_name, city)` — 路線即時車輛位置

**BusCity 22 個代碼**：`Taipei`, `NewTaipei`, `Taoyuan`, `Taichung`, `Tainan`, `Kaohsiung`, `Keelung`, `Hsinchu`, `HsinchuCounty`, `MiaoliCounty`, `ChanghuaCounty`, `NantouCounty`, `YunlinCounty`, `ChiayiCounty`, `Chiayi`, `PingtungCounty`, `YilanCounty`, `HualienCounty`, `TaitungCounty`, `KinmenCounty`, `PenghuCounty`, `LienchiangCounty`

### Bike (3) — YouBike 1.0 + 2.0
- `bike_search_stations(query, city, service_type?)` — 站名搜尋；`service_type` 為 `YouBike1.0` 或 `YouBike2.0`
- `bike_stations_nearby(lat, lon, city, radius_m?)` — 距離排序 + 即時可借／可還車（radius_m 預設 500，clamp 至 50-3000）
- `bike_status_station(station_id, city)` — 單站即時可借／可還

### Air (3) — IATA code
- `air_list_airports()` — 台灣機場總覽
- `air_find_flights(airport, direction, flight_number?)` — 排程查詢；direction 為 `Arrival` 或 `Departure`
- `air_status_flights(airport, direction)` — 即時 FIDS 動態板

### Traffic (3)
- `traffic_freeway_live(road_id?)` — 國道路段即時車速／壅塞等級
- `traffic_incidents(keyword?)` — 交通新聞／施工封閉（5 min cache）
- `traffic_cctv(road_id?)` — CCTV 即時影像串流 URL

### Parking (2)
- `parking_list_lots(city, keyword?)` — 路外停車場名單
- `parking_status(city, lot_id?)` — 即時剩餘車位

**ParkingCity** 與 BusCity 共用 22 個代碼，但 TDX 停車場資料 coverage 主要集中在六都與主要縣市；偏遠縣市可能回空陣列（empty ≠ error）。

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
