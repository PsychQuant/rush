# che-transport-mcp 設計規格

**日期**：2026-05-20
**狀態**：Design draft（已通過 brainstorming，待 writing-plans 階段）
**作者**：鄭澈 (che)

## 目的

為個人與一般使用提供「臺灣所有交通即時狀況」的查詢 MCP，包覆 TDX 運輸資料流通服務（<https://tdx.transportdata.tw/>）為 LLM 友善的工具集。

主要使用情境：

1. 找班次（鐵路、公車、客運、航班、渡輪）
2. 即時誤點 / 到站 / 位置查詢
3. 即時路況、停車場剩餘車位、YouBike 可借可還

## 不在 scope 內

- **跨模式路徑規劃**（捷運 → 公車 → 單車最佳路線）— Google Maps 已有，MCP 補不上
- **訂票** — TDX 無訂票 endpoint
- **歷史資料查詢** — 名稱即「即時」，過去資料非設計目標

## 1. 專案輪廓

### 命名

`che-transport-mcp`（對 user 語義清楚，匹配既有 `che-<noun>-mcp` 命名）。

### 目錄結構

```
/Users/che/Developer/che-mcps/che-transport-mcp/
├── Package.swift                 # MCP swift-sdk 0.12+
├── Sources/CheTransportMCP/
│   ├── main.swift                # MCP server entry
│   ├── TDXClient.swift           # OAuth2 + HTTP layer
│   ├── Cache.swift               # 共用 cache layer（TTL-based）
│   ├── Auth.swift                # Keychain credential 存取
│   └── Tools/
│       ├── RailTools.swift       # 台鐵 / 高鐵 / 各捷運
│       ├── BusTools.swift        # 市公車 + 國道客運
│       ├── BikeTools.swift       # YouBike
│       ├── AirTools.swift        # 國內外航線
│       ├── MaritimeTools.swift   # 渡輪
│       ├── TrafficTools.swift    # 即時路況
│       └── ParkingTools.swift    # 停車場即時車位
├── Tests/CheTransportMCPTests/
├── mcpb/                         # MCP Bundle for Claude Desktop
├── scripts/                      # build / release / setup
├── Makefile                      # release-signed pipeline
├── CLAUDE.md                     # 含 NSQL 引用、tool 使用 discipline
└── docs/
```

### Repo 與 marketplace

- 獨立 git repo，作為 `che-mcps` 的 submodule（與 `che-ical-mcp` 等並列）
- 採同款 Developer ID + notarize pipeline（`make release-signed`）
- 發布為 `psychquant-claude-plugins` 的 plugin

## 2. 認證與憑證儲存

### TDX OAuth2 流程

OAuth2 client credentials grant：

1. 使用者於 <https://tdx.transportdata.tw/register> 註冊（一次性）
2. 取得 `client_id` + `client_secret`
3. MCP 啟動以 client credentials 換 access token（TTL 1 day）
4. Token cache in-memory，過期前自動 refresh

### Keychain 儲存

- Service name：`che-transport-tdx`
- 不支援多帳號（YAGNI — 個人 MCP）
- 不寫 `.env`（多一個漏洞）

### Setup 體驗

```bash
make setup-tdx
```

互動式 prompt 收 client_id / secret → 寫入 keychain → 跑 health check 驗證。Wrapper script 啟動時讀 keychain；missing 則回 MCP error 提示跑 setup。

## 3. Tool catalog（共 23 個）

### 共通 pattern

每個 mode 內部三段式命名：

| Pattern | 用途 | 範例 |
|---------|------|------|
| `<mode>_search_*` | 模糊查 → ID | `rail_search_stations("台北")` |
| `<mode>_find_*` | 規劃查詢：O/D 找方案 | `rail_find_trains(from, to, date)` |
| `<mode>_status_*` | 即時狀態：給 ID 看現況 | `rail_status_train(train_no)` |

### Rail（5 tools）台鐵 / 高鐵 / 各捷運與輕軌

- `rail_search_stations(query, system?)` — 站名 → station_id
- `rail_find_trains(from, to, date, time?, system?)` — O/D 找班次（含票價、車種）
- `rail_status_train(train_no, system)` — 特定車次即時誤點 / 位置
- `rail_status_station(station_id, window_min?)` — 站到站板：近期到站列車 + 誤點
- `rail_list_systems()` — 列出支援的 systems（TRA / THSR / TRTC / TYMC / KRTC / TMRT / NTDLRT / KLRT）

### Bus（5 tools）市公車 + 國道客運

- `bus_search_routes(query, city?)` — 路線名 / 編號搜尋
- `bus_search_stops(query, city?)` — 站名搜尋
- `bus_find_routes(from_stop, to_stop, city?)` — O/D 找候選路線
- `bus_status_arrivals(stop_id, city?)` — 站近期到站預測
- `bus_status_positions(route_id, city?)` — 路線上即時位置

### Bike（3 tools）YouBike

- `bike_search_stations(query, system?)` — 站名搜尋
- `bike_stations_nearby(lat, lon, radius_m, system?)` — 附近站 + 即時可借可還
- `bike_status_station(station_id)` — 單站即時可借可還

### Air（3 tools）

- `air_search_airports(query)` — 機場 IATA / 中文名搜尋
- `air_find_flights(from, to, date?)` — 班機搜尋
- `air_status_flight(flight_no, date?)` — 即時誤點 / 登機門 / 跑道

### Maritime（2 tools）

- `maritime_search_routes(query?)` — 航線搜尋
- `maritime_find_schedule(route_id, date?)` — 該航線時刻

### Traffic（3 tools）

- `traffic_status_freeway(road?, direction?)` — 即時車速與壅塞
- `traffic_list_incidents(area?, road?)` — 事故 / 施工 / 封閉
- `traffic_cctv_snapshot(camera_id?, road?)` — CCTV 即時影像 URL（回 URL，不下載）

### Parking（2 tools）

- `parking_lots_nearby(lat, lon, radius_m)` — 附近停車場 + 即時剩餘車位
- `parking_status_lot(lot_id)` — 單一停車場即時車位

## 4. Cache 與 Rate Limit

### TDX 配額（免費版）

- 每分鐘 50 次
- 每日 200 萬次

### Cache 三段

| 資料類型 | TTL | 理由 |
|----------|-----|------|
| 靜態（站點、路線、車種） | 24h | 半年才變一次 |
| 時刻表（每日時刻） | 1h | 通常隔日才變 |
| 即時（誤點、到站、車位） | **0s（不 cache）** | 賣點就是「即時」 |

### Cache 實作

`Cache.swift` 提供 actor-based in-memory TTL cache：

- Key = endpoint URL + sorted query params 的 hash
- 啟動時空白，不寫硬碟
- 每個 tool 自己指定 TTL

### Rate Limit 防線

1. 429 後 sleep 1s 重試一次（最多一次）
2. 第二次 429 直接 fail，附 message「TDX rate limit; 稍後再試」
3. 不做 background queue（MCP stateless）

## 5. Error Handling

### 錯誤分類

| 類別 | 觸發 | MCP 回應 |
|------|------|----------|
| Auth 錯誤 | credentials 缺 / 無效 | `MCPError("TDX credentials missing or invalid. Run: make setup-tdx")` |
| Rate limit | 429（已重試）| `MCPError("TDX rate limit exceeded; retry in 60s")` |
| 網路 | timeout / DNS / TLS | `MCPError("Network error: <detail>")` |
| 空資料 | 查無 | **正常 return** `{ "results": [] }` |
| 無效輸入 | 站名不存在、日期格式錯 | `MCPError("Invalid <field>: ...; <hint>")` |
| TDX 5xx | 後端故障 | `MCPError("TDX service unavailable (HTTP 503)")` |
| Schema drift | TDX 改格式 | `MCPError("TDX response format changed; please file an issue")` |

### 設計原則

1. **空 ≠ 錯**：「沒查到」走 normal return，error 只用於系統性問題
2. **錯誤訊息含「下一步」**：每個錯誤告訴使用者怎麼處理
3. **不吞錯**：所有錯誤 propagate 給 LLM
4. **不靜默重試**：除 429 單次 retry，其他 fail fast

### Edge cases（提前防）

1. **站名同名**：「中山」需回所有匹配（附 system 標籤）讓 LLM / user 選擇
2. **時區**：`TDXClient` parser 統一轉為 `Asia/Taipei`，對外只回 ISO8601 with `+08:00`
3. **跨日班次**：date 指「發車日」，文件須明確
4. **YouBike 1.0 vs 2.0**：兩個 TDX endpoint，`bike_*` 預設查 2.0，提供 `system` param 切換

## 6. Testing

### 三層配置

| 層級 | 範圍 | TDX 憑證需求 | CI |
|------|------|--------------|----|
| Unit | parsing、cache、fuzzy match、TZ 轉換 | ❌ fixture JSON | ✅ |
| Integration | OAuth2、tool 對真 TDX、429 retry | ✅ keychain | ❌（local only） |
| Smoke | 23 tools 各 invoke 一次成功 | ✅ | ❌（手動） |

### Unit test 重點

1. Parser tests — 每 mode 至少 1 個 fixture JSON
2. Cache tests — set/get/expiry/actor concurrent
3. Fuzzy match — 「中山」應回多個候選
4. Time zone — UTC ↔ +08:00 互轉
5. Error mapping — 429 → rate limit error，401 → auth error

### Integration test 設計

- 每 mode 一個 test method
- 不檢查具體值（會變動），只檢查回應 schema：JSON top-level 結構符合預期、必填欄位（如 `train_no`、`station_id`、`departure_time`）存在、時間欄位符合 ISO8601 with `+08:00`
- 跑前檢查 keychain；無 credential 則 `XCTSkip`（不擋 build）

### YAGNI

- 不做 mock TDX server
- 不做 load testing
- 不做 contract testing（TDX 無 backward compat 承諾）

## 7. Interaction discipline（NSQL）

`CLAUDE.md` 必須引用 <https://github.com/kiki830621/NSQL> 作為使用此 MCP 的 LLM 互動準則。

### 為什麼適用

雖然此 MCP 為 read-only query，無「執行風險」，但**輸入歧義頻繁**：

- 「中山」站 → 紅線？淡水線？桃捷？台中？
- 「下一班」→ 時間錨點為何？
- 「往台北」→ 起站為何？

LLM 在呼叫 tool 前應依 NSQL protocol：

1. 把 user query 分解為 function + arguments
2. 將解析結果回顯給 user 確認
3. 確認後才呼叫 tool

### 範例

> User: 「下一班高鐵」
>
> LLM（依 NSQL 範式）：「我理解你要查 (起站) → (迄站) 從 (現在時間) 起的下一班高鐵。請問起迄站？」
>
> User: 「台北到左營」
>
> LLM：「即將呼叫 `rail_find_trains(from='Taipei', to='Zuoying', system='THSR', time='now')`。確認嗎？」
>
> User: 對 → LLM 呼叫 tool

### CLAUDE.md 內容（要點）

CLAUDE.md 應該：

- 明確說明此 MCP 採 NSQL interaction discipline
- 連結到 NSQL repo
- 列出常見歧義場景與建議的 confirmation phrasing

## 8. 開發路徑

依 brainstorming 結論：

- Swift native（與既有 che-mcps 一致）
- 全 7 類 mode 一次上 v0.1
- 估時 2-3 週

## 9. 未決事項

無 — 所有設計問題已於 brainstorming 階段釐清。

## 10. 下一步

進入 `superpowers:writing-plans` skill，產出 implementation plan（含 phase 拆分、TDD 順序、commit checkpoint）。
