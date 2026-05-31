## Context

捷運在 che-transport-mcp 只有站點搜尋與即時站牌板，無 O/D 路線查詢（#5）。`rail_find_trains` 僅支援 TRA/THSR（固定時刻 DailyTrainTimetable/OD）。捷運按班距營運，無固定時刻表，所以「O/D」的自然形狀是「連接線 + 旅行時間 + 班距」而非「某班車幾點」。

實測 TDX 捷運端點（v2/Rail/Metro/{Dataset}/{op}，dataset 在 operator 前，沿用 #4 的 metro 路徑慣例）：
- StationOfRoute：每 route 的 Stations 清單（取交集找直達線）
- S2STravelTime：站到站旅行時間（累加 from→to 區段）
- Frequency：依 ServiceDay + OperationTime 的 Headways（班距）
- Line：LineName / LineColor（輸出可讀化）

約束：TDX free tier rate limit（contract test sequential + 間隔）；沿用 #4 的 TDXEndpoints registry + live contract 框架。

## Goals / Non-Goals

**Goals:**

- 新 MCP tool 查捷運直達 O/D，回連接線 + 旅行時間 + 班距。
- 4 個 metro 端點納入 TDXEndpoints registry 單一事實來源 + contract case。
- 跨 6 個 metro 系統可用（資料稀疏系統回空，empty ≠ error）。

**Non-Goals:**

- 轉乘路線規劃（→ #6）。
- 跨運具整合、即時班次配對、擴充 rail_find_trains。

## Decisions

### 新 tool metro_find_route，不擴充 rail_find_trains

新增 tool metro_find_route(from, to, system)。捷運回傳形狀（線+旅行時間+班距）與 TRA train list 根本不同，混入 rail_find_trains 會讓 system enum 與回傳 schema 依 system 分裂。新 tool 邊界清楚。

替代方案：擴充 rail_find_trains 接受捷運 system。否決——回傳形狀不一致，dispatch 與 schema 都變醜。

### v1 只做直達（單 route 交集）

用 StationOfRoute 找「單一 route 的 Stations 同時含 from + to」即直達。若無單一 route 涵蓋兩站 → 回空 matches + 提示需轉乘（指向 #6），不在 v1 嘗試組合多線。

理由：直達是站集合交集 + 區段累加，無需圖演算法；轉乘是換乘站推導 + 路徑最佳化，複雜度懸崖，獨立成 #6 才能讓本 change「一件事、可獨立 verify」。

### 回傳形狀：line + travel time + headway

對找到的直達 route：取 Line 的 LineName/LineColor、S2STravelTime 累加 from→to 區段秒數轉分鐘、Frequency 取當下 ServiceDay+OperationTime 的 Headway。回傳結構含 routes 陣列（可能多 route/方向命中）。

替代方案：只回「搭某線」不含時間/班距。否決——時間與班距是 O/D 查詢的核心價值。

### 4 個 metro 端點進 TDXEndpoints registry

沿用 #4 框架：在 TDXEndpoints 加 metroStationOfRoute/metroS2STravelTime/metroFrequency/metroLine builder（依 system code）+ 對應 contract case。production（MetroTools）與 contract test 都引用 registry，無 inline 路徑字面值。

### 路由邏輯資料流

metro_find_route 內：StationOfRoute 找含 from+to 的 route（判方向）→ 該 route 的 Stations 序列定位 from/to index → S2STravelTime 累加區間 → Frequency 查當下班距 → Line 補線名/顏色 → 組裝回傳。各 fetch 經 registry builder。

## Implementation Contract

- **Behavior**：metro_find_route(from, to, system) 對有直達線的捷運 O/D 回該線 + 旅行時間（分）+ 當下班距（分）；無直達線回空 matches + 轉乘提示（指 #6）；資料稀疏系統回空（empty ≠ error）。
- **Interface / data shape**：輸入 from（StationID，由 rail_search_stations 取得）、to（StationID）、system（6 個 metro 代碼之一）。輸出 routes 陣列，每筆含 line_name、line_color、route_name、direction、travel_time_min、headway_min、stations_count；外層附 from/to/system。
- **Failure modes**：invalid system / 缺參數 → decoding error；無直達 → 空 matches + note 非 error；TDX HTTP/network/rate-limit error 照常 surface（沿用 TDXClient）。
- **Acceptance criteria**：(1) metro_find_route(臺北車站→南港, TRTC) 回板南線直達 + 旅行時間 + 班距；(2) TDXEndpoints 含 4 個 metro builder + contract case，TDX_CONTRACT=1 下綠；(3) tool 總數 22、MCPJSONRPCSmokeTest 斷言更新；(4) 離線 swift test 全綠不需網路；(5) production 無 registry 以外的 metro 路徑字面值（grep 驗證）。
- **Scope boundaries**：in scope = 單一捷運系統內直達 O/D + 4 端點 registry/contract + 新 tool/model + docs。out of scope = 轉乘（#6）、跨運具、即時班次、rail_find_trains 擴充。

## Risks / Trade-offs

- [站 ID 對應] from/to 的 StationID 需與 StationOfRoute 的 Stations[].StationID 一致 → apply 時用 rail_search_stations 取得的 ID 實測對齊。
- [6 系統資料差異] 輕軌（NTDLRT/KLRT）Frequency/S2STravelTime 可能稀疏 → 空欄位回 -1/空，不 error；contract test 首跑揭露。
- [多 route 命中] 同兩站可能有多 route/方向（如區間車 vs 全程）→ 回 routes 陣列全列，client 端選。
- [班距時段判定] Frequency 依 ServiceDay（平日/假日）+ OperationTime（時段）→ 需以查詢當下 Asia/Taipei 時間配對；無對應時段回最近一筆 + 標註。

## Migration Plan

純增量，無資料遷移。順序：registry 加端點 → MetroModels → MetroTools 路由邏輯 → 註冊 tool → 測試 → docs。rollback：移除新檔 + registry 條目 + 註冊即可。

## Open Questions

- 多 route 命中時的排序（旅行時間？route 名？）——apply 時以「旅行時間升冪」為預設，可調。
- Frequency 無當下時段對應時的 fallback（回最近時段 vs 回空）——傾向回最近時段 + 標註。
