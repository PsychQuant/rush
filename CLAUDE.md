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

# CLAUDE.md — rush

This file is read by LLM agents (Claude Code, Codex, etc.) that use this MCP server. Follow these conventions to avoid common pitfalls.

## North Star — 臺灣版的 NAVITIME

這個 MCP 的目標是成為**臺灣版的 [NAVITIME](https://www.navitime.co.jp/)**：一個 MCP-native、time-dependent、live-aware 的大眾運輸路由引擎（OpenTripPlanner / RAPTOR-class），把台灣各運具的路由做深。

**誠實的天花板**：路由準確度的上限是 **TDX 的資料形態，不是演算法**。NAVITIME 之所以準，靠的是資料（全業者班次時刻表 + 即時運行情報 + 實測站內轉乘步行時間），不是祕密演算法——演算法（RAPTOR/CSA/time-dependent search）是公開的，我們用的是同一家族。所以：

- TDX 資料豐富處（TRA/THSR 有 per-train 時刻表 + `TrainLiveBoard` 即時誤點）→ 我們能做到 NAVITIME 等級的精確。
- TDX 資料薄處（捷運/公車只給 headway 班距、**無 per-vehicle 發車 phase**）→ 我們用誠實的 expected-wait 模型（`E[wait] = headway/2`）並標 `source: frequency`，不假裝精確。
- 要逼近 NAVITIME 的捷運準度 = **資料採集問題**（補 phase 時刻表），屬 Stage 3+，不是改演算法能解的。

路由引擎分階段建（內部代號 (B) 北極星）：

- **Stage 1**（已出貨 v0.6.0）：`rail_route` — TRA 時刻表 time-dependent 最早抵達 + 即時誤點調整。
- **Stage 2**（已出貨 v0.7.0）：`transit_route` — TRA↔台北捷運多模式路由，scoped 到策劃式 interchange registry；捷運段 expected-wait。
- **Stage 3**（進行中）：公車 + 更完整 live feed + 統一多模式核心。**3a（已實作 v0.8.0）**：`bus_route` 市內公車直達路由（A2 即時上車預估 + 班表抵達／誠實從缺）。**3b-i（已實作 v0.9.0）**：`rail_bus_route` rail→bus 顯式轉乘多模式路由——鐵路段沿用 transit_route 引擎到 transfer 站，於該站以站名比對（`捷運X站`／`X車站`，非裸字串以免行政區 over-match）找公車上車站，公車段以「抵達 transfer + 步行」為錨點（A2 停用：now-snapshot 無法計未來上車，故 schedule／headway 計時，班表抵達或誠實從缺）。**3b-ii（已實作 v0.10.0）**：`rail_bus_route` 的 `transfer` 改為**選填**——省略時自動選交會站：以 `to_stop` 為錨反向搜尋（serving `to_stop` 的公車路線上游站名稱比對鐵路站），對候選交會站跑 rail+bus 取最早抵達，回 `auto_selected_transfer`；候選有上限（預設 8），超過於 note 揭露捨棄數。**3c-i（已實作 v0.11.0）**：`bus_rail_route` bus→rail 多模式路由（rail_bus_route 的鏡像）——公車 leg 1 上車在旅程起點故 **A2 即時可用**（`source: live`）；以 `from_stop` 為錨正向搜尋下游站名稱比對找下車鐵路站（transfer 選填／自動），鐵路段用 transit_route 引擎以「公車抵達 + 步行」錨定；公車抵達未知（frequency-only）時改以上車+步行錨定 rail 並加近似 note。**3c-ii.1（已實作，內部）**：`RaptorCore` 統一路由核心——**多策略 ensemble + dominance 選擇器**（不是單一演算法）：`ComposedStrategy`（委派既有 TRA+捷運組合 = floor，永不退化）+ `RaptorStrategy`（round-based、可達 ≥2-transfer、委派子引擎成本故不會低估），選最早抵達（平手比轉乘少、再平手依註冊序）。經差異等價 harness 驗證重現 `transit_route`（TRA→捷運／捷運／TRA／不可達四案），**尚未接線任何 tool、工具數維持 27、不改使用者可見行為**。原則：proven 為 floor、新策略只增可達不減精度（headway/2 期望天花板不變）。**3c-ii.2（已實作，內部）**：`transit_route` 已遷移為委派 `RaptorCore.plan([Composed, Raptor])`（`Journey` 補 `transfers` 後 executor 由 Journey 重建 payload），行為 byte-identical、以 frozen `TransitToolsTests` 為 regression gate；工具數維持 27、無使用者可見變化。**3c-ii.3（已實作，內部）**：剩餘四 tool 全數 dispatch 經 `RaptorCore`——`rail_bus_route`／`bus_rail_route` 的鐵路段經共用 `composeRailLeg`→`plan([Composed, Raptor])`；`bus_route`／`metro_find_route` 經委派 facade（`planBusDirect`→`BusRouter`、`planMetroRoutes`→`MetroGraph` by-time+by-transfers）。**單模式 tool 的 facade 為結構性 routing-through-the-core（委派 proven 引擎），非 ensemble／multi-transfer 能力**（誠實標記：bus-only／metro-only 0–1 transfer，ensemble 對它們無增益；價值在統一 dispatch）。五個 routing tool 現皆經核心、行為 byte-identical、各以 frozen 測試為 gate；工具數維持 27、無使用者可見變化。**下一步（未來，需求驅動）**：`journey_plan` ≥2-transfer 工具——核心 `RaptorStrategy` round 引擎已可達 ≥2 轉乘，待真實需求出現再開 surface。

## What this MCP does

Provides 27 tools over the [TDX 運輸資料流通服務](https://tdx.transportdata.tw/) covering 6 transport modes in Taiwan: Rail (TRA / THSR / 各捷運與輕軌), Bus, Bike (YouBike), Air, Traffic, Parking.

Current build covers **all 27 tools across 6 modes**. Per-module tool catalogue below.

> **Maritime (航運/渡輪) is not covered.** TDX no longer serves it on the unified API (every `v2`/`v3` `Maritime`/`Ship` path 404s) and the legacy PTX `Ship` API is decommissioned (403 regardless of auth). The contract suite confirmed there is no callable maritime endpoint, so those tools were removed rather than ship broken. See PsychQuant/rush#4.

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
make setup-tdx                 # one-time, interactive (wraps Rush --setup)
# or directly, once the binary is built/installed:
Rush --setup
```

`--setup` prompts for TDX `client_id` / `client_secret`（register at <https://tdx.transportdata.tw/register>），writes them to the macOS keychain under service `che-transport-tdx`, and verifies with a live OAuth round-trip. The secret prompt uses `getpass` so it never echoes.

## Tools (27 total across 6 modes)

### Rail (7)
- `rail_list_systems()` — 列出 8 個支援 system
- `rail_search_stations(query, system?)` — 模糊搜尋站點 → station_id（未指定 system 會並行 fan-out）
- `rail_find_trains(from, to, date, system)` — O/D 找班次（僅 TRA / THSR）
- `rail_status_train(train_no, system)` — 特定列車即時誤點
- `rail_status_station(station_id, system)` — 站到站板（即時）
  - Note: `window_min` 參數在 schema 中接受（forward-compatibility），但目前 **未生效** — TDX `StationLiveBoard` endpoint 自帶預設視窗。Client-side 視窗過濾預計 v0.3 加入。
- `metro_find_route(from, to, system)` — 捷運 O/D 路線（含跨線轉乘）：建站網圖跑最短路徑，回 routes[]，每條含 legs（每段線+時間+班距）+ transfers（換乘站+步行+估計等車）+ transfer_count + 總時間。直達 = 0 transfer。
- `rail_route(from, to, depart_after?, system)` — TRA 時刻表 time-dependent 最早抵達路由：套用 TrainLiveBoard 即時誤點調整（誤點班次可能被較晚但實際更早到的車取代），回 legs（車次/起訖/開到時刻/誤點/source）+ arrival_time + duration_min。僅 TRA；與 rail_find_trains（列班次）不同。

### Multi-modal (3) — Stage 2–3c of the (B) routing engine
- `transit_route(from, to, depart_after?)` — TRA↔台北捷運（TRTC）多模式最早抵達路由。time-anchored 組合：TRA 段用時刻表 + 即時誤點（`source: live`），捷運段用班距期望等車 `E[wait]=headway/2`（`source: frequency`，TDX 捷運無 per-vehicle phase 故無 live）。跨系統轉乘僅限策劃的 interchange registry（台北車站/板橋/南港/松山）。回 legs（每段 mode + 起訖 + 時刻 + source）+ transfers（交會站 + walk_min）+ arrival_time + duration_min + transfer_count。站名多系統同名 → 回 `matches` 釐清；查無路徑 → `routes:[] + note`（empty ≠ error）。僅 TRA + TRTC；公車／其他捷運／THSR 不在此 stage。
- `rail_bus_route(from, to_stop, city, transfer?, depart_after?)` — **rail→公車**多模式路由（Stage 3b）。`transfer` **選填**：給定時走該站轉乘（3b-i）；省略時自動選交會站（3b-ii）——以 `to_stop` 為錨反向搜尋（serving `to_stop` 的公車路線，對 `to_stop` 上游站做站名比對找鐵路站），對候選交會站跑 rail+bus 取最早抵達，輸出 `auto_selected_transfer` 標示選中站；候選有上限（`maxAutoHubCandidates`=8，依離 `to_stop` 接近度取前 N），超過於 `auto_hub_note` 揭露捨棄數。鐵路段沿用 `transit_route` 引擎（`source: live/scheduled/frequency`）；站名比對 `捷運X站`／`X車站`／`X火車站`，正規化 `臺`↔`台`，**非裸字串**以免行政區 over-match（`南港` 接受 `南港車站` 但拒 `南港高工`）。公車段以「抵達 transfer + 步行（估計 5 分）」為發車錨點——**A2 即時停用**（now-snapshot 無法計未來上車），改用班表發車（`source: scheduled`）／班距期望（`source: frequency`），班表抵達 `source: scheduled`、frequency-only 抵達從缺 + note。回 legs（鐵路各段 + 一段 Bus）+ transfers（transfer 站 + walk_min，步行為估計值）+ arrival_time + duration_min + transfer_count(=1)。站名多筆同名 → `matches`；鐵路不可達／無對應上車站／無直達 → `routes:[] + note`（empty ≠ error）。僅 rail→bus 單轉乘、TRA+TRTC 鐵路段；bus→rail 見 `bus_rail_route`；多段為 3c-ii。
- `bus_rail_route(from_stop, to, city, transfer?, depart_after?)` — **公車→鐵路**多模式路由（Stage 3c-i，`rail_bus_route` 的鏡像）。公車段為 leg 1、上車在旅程起點故 **A2 即時可用**（`source: live`；無則班表 `source: scheduled`／班距 `source: frequency`）。`transfer` **選填**：給定時於該站下車；省略時自動選下車站——以 `from_stop` 為錨**正向**搜尋（serving `from_stop` 的公車路線，對 `from_stop` **下游**站做站名比對找鐵路站），對候選下車站跑 bus+rail 取最早 rail 抵達，輸出 `auto_selected_transfer`；候選上限同 3b-ii（8，依離 `from_stop` 接近度），超過於 `auto_hub_note` 揭露捨棄數。鐵路段用 `transit_route` 引擎，以「公車抵達交會站 + 步行」為 `departAfter`；**公車抵達未知（frequency-only）時改以上車時刻 + 步行錨定 rail 並加 `approx_note`，不假裝精確**。回 legs（一段 Bus + 鐵路各段）+ transfers（交會站 + walk_min，步行為估計值）+ arrival_time（rail 抵達）+ duration_min + transfer_count(=1)。`from_stop`／`to` 多筆同名 → `matches`；無對應下車站／rail 不可達／無直達 → `routes:[] + note`（empty ≠ error）。僅 bus→rail 單轉乘、TRA+TRTC 鐵路段；multi-transfer／RAPTOR 為 3c-ii。

### Bus (6) — city 必填
- `bus_search_routes(query, city)` — 路線模糊搜尋
- `bus_search_stops(query, city)` — 站牌模糊搜尋
- `bus_find_routes(from_stop, to_stop, city)` — O/D 候選路線（從 `StopOfRoute` 交集）
- `bus_status_arrivals(stop_id, city)` — 站牌即時到站預估
- `bus_status_positions(route_name, city)` — 路線即時車輛位置
- `bus_route(from_stop, to_stop, city, depart_after?)` — 市內公車**直達**路由（Stage 3a；暫不含轉乘）。回經過兩站（起站在迄站之前、同方向）的直達路線，每條附上車預估（A2 即時 `source:live`／班表發車 `source:scheduled`／班距期望 `source:frequency`）+ 抵達時刻（有班表才給 `source:scheduled`；frequency-only 路線抵達從缺 + note，不假裝精確）。站名多筆同名 → `matches`；無直達 → `routes:[] + note`。

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

See `docs/superpowers/specs/2026-05-20-rush-design.md` for full design.
Bus ETA prediction methodology (metric = time in seconds, covariates, ceiling): `docs/bus-eta-prediction.md`.

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
swift run Rush --version
```

## Bus ETA Logger — 資料儲存位置（mini-che 外接 NVMe）

> 對應 change `openspec/changes/bus-eta-logger`（Stage 3+ 資料採集層）。logger 為獨立 **Python** 常駐程序，跑在 **mini-che（PsychQuantMini，che830621 帳號，常開）**，**與本 read-only MCP 分離**。TDX 公車動態僅滾動保留 ~2h、無任何現成歷史來源（已查證），故須自記——源頭即丟，誰先記誰獨有。

**Canonical 儲存根**（mini-che 外接 USB4 NVMe：PROBOX 盒 + Kingston NV3 2TB）：

```
/Volumes/mini-2TB-SSD/che-transport/bus-eta/
├── parquet/                                                       # fact 表（BCNF thin-fact：只存 FK + 量測 + 時間）
│   ├── arrival_event/city=<code>/date=<YYYY-MM-DD>/*.parquet     #   A2 去重後到站事件（到站真值）
│   ├── vehicle_position/city=<code>/date=<YYYY-MM-DD>/*.parquet  #   A1 即時車輛 GPS 位置（全量，不去重）
│   └── eta_snapshot/city=<code>/date=<YYYY-MM-DD>/*.parquet      #   N1 ETA baseline 對照
├── dim/                                                           # SCD Type-2 dimension（route/stop/vehicle/route-stop bridge；valid_from/valid_to/is_current）
├── gaps/                                                          # gap marker（logger 中斷的不可回補缺漏時段）
└── serving/                                                       # 預算表（Phase 2：P50/P80 → bus_eta_predict）
```

- **Volume 名 = `mini-2TB-SSD`**（Kingston NV3 2TB；已掛載於 `/Volumes/mini-2TB-SSD`，`diskutil` 報 PCI-Express、Removable: Fixed）。
- **掛載守衛**：碟未掛載時 logger **拒絕寫入、不可 fallback 到系統碟（256G）**。
- 查詢引擎 = DuckDB；分析 = SSH 進 mini-che 在地跑或 rsync Parquet 回筆電（**勿隔 SMB 即時查**，延遲會咬）。
- **對齊分析**：`analysis/spine.sql` 定義 DuckDB views（a1/a2/n1/arrivals）+ ASOF marts：`trajectory(t0,t1,step_sec)`（車軌跡，A1 位置前向填）、`prediction_error`（每筆到站 vs N1 預測的誤差；N1 無 plate 故 join 在 route/dir/stop）。mini 無 duckdb CLI → 用 logger venv 的 python duckdb（已裝 `pytz` 供 timestamptz 輸出）：`con.execute(open('analysis/spine.sql').read())`。
- **路線視覺化**：`analysis/marey.py <route>`（站序 Marey 時空圖，`--normalize` 出 run-time profile）、`analysis/spacetime.py <route>`（A1 GPS 投影到路線 Shape 的**真距離** distance-time，slope=真 km/h；含清洗：濾 `duty_status=1`&`bus_status=0`→投影丟 >200m 離線→切趟→覆蓋率≥80%&前進率≥80%，`--keep-anomalies` 灰線疊示被丟趟）。產生的 PNG 在 `analysis/output/`（gitignored）。
- **採集 feeds（3 條，各自節奏）**：`A2`(30s)→`arrival_event`（到站真值，去重）／`A1`(10s)→`vehicle_position`（即時車輛 GPS 位置，全量不去重；A2/N1 都不帶座標，位置只在 A1）／`N1`(120s)→`eta_snapshot`（ETA 預測基準）。A1 取 10s 是對應實測 TDX GPS 更新率 ~15–20s（再細是重複、源頭沒那麼細）。
- 涵蓋範圍：大臺北（Taipei + NewTaipei）。異地備份：Dropbox / R2。

### 部署現況（2026-06-09 起跑）

logger 已部署並運行於 mini-che，capture-feasibility 7 天 run 進行中（Taipei + NewTaipei）。部署踩過三道 macOS 關卡，操作需求記錄如下：

| 項目 | 值／路徑 | 為什麼 |
|------|----------|--------|
| launchd agent | `~/Library/LaunchAgents/tw.psychquant.bus-eta-logger.plist`，GUI domain 載入（`launchctl bootstrap gui/$(id -u) <plist>`）| RunAtLoad + KeepAlive 常駐；env 帶 `BUS_ETA_VOLUME=/Volumes/mini-2TB-SSD` + `BUS_ETA_DATA_ROOT=.../parquet` |
| TDX 憑證 | **600 本機檔** `~/.config/bus-eta-logger/tdx.json`（`{client_id, client_secret}`），**非 keychain** | launchd 讀 keychain 會卡授權對話框（classic ACL + partition list 兩道閘都認 che-keychain、不認 launchd 的 python）。改檔案 daemon 讀取永不跳框。poller `_load_creds()` 優先讀此檔、fallback keychain；檔不進 git／不上 NVMe |
| Full Disk Access | 授 FDA 給 `/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9` | macOS TCC 擋 launchd 的 python 寫 `/Volumes` 外接卷宗（EPERM）；ssh 能寫（sshd 已授權）但 launchd 不行，須在「系統設定 → 隱私權 → 完整取用磁碟」加該 python |

- **重啟 agent**：`ssh mini-che 'launchctl kickstart -k gui/$(id -u)/tw.psychquant.bus-eta-logger'`
- **看狀態**：`ssh mini-che 'launchctl list | grep bus-eta; tail ~/Library/Logs/bus-eta-logger.err.log'`
- **查資料量**：`ssh mini-che 'find /Volumes/mini-2TB-SSD/che-transport/bus-eta/parquet -name "*.parquet" | wc -l'`
