# che-transport-mcp

提供臺灣即時交通查詢的 MCP server，資料來源為 [TDX 運輸資料流通服務](https://tdx.transportdata.tw/)。

[English README](README.md) · [Design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md) · [v0.2 backlog](docs/v0.2-backlog.md)

## 狀態

**v0.2-dev** — 25 個 tools，涵蓋 6 種交通模式（鐵路 / 公車 / 共享單車 / 航空 / 路況 / 停車場），含 `transit_route`（台鐵↔台北捷運多模式）+ `bus_route`（市內公車直達、A2 即時上車預估）

Roadmap:
- v0.1: Rail ✅（5 工具）
- v0.2: 公車 + YouBike ✅（8 工具）
- v0.3: 航班 ✅（3 工具；渡輪移除——TDX 無可呼叫的海運 API，見 #4）
- v0.4: 路況 + 停車場 ✅（5 工具）
- v1.0: Release pipeline + marketplace 上架

## 快速開始

```bash
git clone <repo>
cd che-transport-mcp
make build
make setup-tdx   # 互動式收 TDX 憑證
```

TDX 帳號免費註冊：<https://tdx.transportdata.tw/register>

## Tools

### 鐵路（7）

| Tool | 用途 |
|------|------|
| `rail_list_systems` | 列出 8 個支援 rail system（台鐵／高鐵／4 個捷運／2 個輕軌） |
| `rail_search_stations` | 站名模糊搜尋（跨 system 平行查詢）|
| `rail_find_trains` | O/D + 日期找班次（台鐵 / 高鐵）|
| `rail_status_train` | 特定列車即時誤點 |
| `rail_status_station` | 站到站板（即時）|
| `metro_find_route` | 捷運 O/D 路線（含跨線轉乘）：站點網路最短路徑，回 `legs[]`（每段所搭路線）+ `transfers[]`（每次換線，含步行 + 預估候車）+ `transfer_count` + 總旅行時間（直達 = 0 transfer 路徑）|
| `rail_route` | TRA 時刻表 time-dependent O/D 路由：真實時刻表最早抵達 + 即時誤點調整，回 legs + arrival_time + duration_min；僅 TRA |

### 公車（5）

| Tool | 用途 |
|------|------|
| `bus_search_routes` | 城市內路線模糊搜尋 |
| `bus_search_stops` | 城市內站牌模糊搜尋 |
| `bus_find_routes` | O/D 候選 — 找同時經過兩站的路線 |
| `bus_status_arrivals` | 站牌即時到站預估 |
| `bus_status_positions` | 路線即時車輛位置 |

公車工具一律 **必填 city** — 22 個 BusCity 代碼（`Taipei` / `NewTaipei` / … / `LienchiangCounty`）。

### 共享單車（3）— YouBike 1.0 + 2.0

| Tool | 用途 |
|------|------|
| `bike_search_stations` | 站名搜尋，可選 service_type 過濾 |
| `bike_stations_nearby` | Haversine 距離排序 + 即時可借／可還車 |
| `bike_status_station` | 單站即時可借／可還車數 |

### 航空（3）

| Tool | 用途 |
|------|------|
| `air_list_airports` | 台灣機場總覽 |
| `air_find_flights` | 依機場 + 到達／離開查當日航班排程 |
| `air_status_flights` | 即時 FIDS 動態板 |

### 路況（3）

| Tool | 用途 |
|------|------|
| `traffic_freeway_live` | 國道路段即時車速與壅塞等級 |
| `traffic_incidents` | 交通新聞／施工封閉（5 min cache + keyword 過濾）|
| `traffic_cctv` | CCTV 即時影像串流 URL 名單 |

### 停車場（2）

| Tool | 用途 |
|------|------|
| `parking_list_lots` | 城市內路外停車場名單 |
| `parking_status` | 即時剩餘車位數 |

## 架構特性

- **唯讀**：25 個 tools 全為 GET，無執行風險
- **三層快取 TTL**：24h（靜態：站點／路線／停車場／CCTV）· 1h（時刻表）· 5-10 min（新聞）· 0s（即時：ETA、位置、FIDS、停車即時資料）
- **Rate limit**：TDX 免費層 50/min。429 觸發一次 1s 重試
- **Empty ≠ error**：空結果是合法回傳，錯誤保留給系統層（auth/network/rate limit）
- **統一 registry**：每個交通模式 append 進 `ToolRegistry`，`Server.swift` 安裝一個 `ListTools` 與一個 `CallTool` handler delegate 到 registry。新增模式只需一個 `Tools/` 檔、一個 `Models/` 檔、一行 `register()`

完整架構見 [design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md)。

## License

MIT。詳見 [LICENSE](LICENSE)。
