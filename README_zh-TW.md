# che-transport-mcp

提供臺灣即時交通查詢的 MCP server，資料來源為 [TDX 運輸資料流通服務](https://tdx.transportdata.tw/)。

[English README](README.md)

## 狀態

**v0.1.0** — 僅 Rail 工具（台鐵 / 高鐵 / 4 個捷運 / 2 個輕軌）

Roadmap:
- v0.1: Rail（本版本）✅
- v0.2: 公車 + YouBike
- v0.3: 航班 + 渡輪
- v0.4: 路況 + 停車場
- v1.0: Release pipeline + marketplace 上架

## 快速開始

```bash
git clone <repo>
cd che-transport-mcp
make build
make setup-tdx   # 互動式收 TDX 憑證
```

TDX 帳號免費註冊：<https://tdx.transportdata.tw/register>

## Tools（Plan 1）

| Tool | 用途 |
|------|------|
| `rail_list_systems` | 列出 8 個支援 rail system |
| `rail_search_stations` | 站名模糊搜尋 |
| `rail_find_trains` | O/D + 日期找班次 |
| `rail_status_train` | 特定列車即時誤點 |
| `rail_status_station` | 站到站板（即時）|

## 架構

詳見 [design spec](docs/superpowers/specs/2026-05-20-che-transport-mcp-design.md)。

## License

MIT。詳見 [LICENSE](LICENSE)。
