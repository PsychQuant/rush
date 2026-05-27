---
name: today-rail
description: Quick rail query helper — find the next train(s) between two stations today on TRA / THSR / metros. Use when user says "下一班高鐵 / 台北到左營 / 下午回新竹的高鐵 / 今天最後一班自強號 / 還來得及搭末班車嗎" or similar O/D timetable queries. Walks NSQL discipline (parse → confirm → call) using rail_search_stations to disambiguate Chinese station names like 中山 / 忠孝 across multiple systems, then rail_find_trains for the actual schedule, optionally rail_status_train for live delay.
allowed-tools:
  - AskUserQuestion
---

# today-rail — quick rail query

Wraps `rail_search_stations` → `rail_find_trains` → optional `rail_status_train` for the most common Taiwan rail use case: "what trains run from A to B today / at this time?"

## NSQL discipline (mandatory)

Per the plugin's CLAUDE.md, **never call rail tools without first parsing user intent into `function + arguments` and confirming with the user**. Common ambiguity:

| User phrase | Question to resolve |
|-------------|---------------------|
| 「中山」「忠孝」 | Multiple systems have same-named stations — TRTC vs TYMC vs Taichung MRT? |
| 「下一班」「最近」 | Time anchor — now (Asia/Taipei) unless user specifies |
| 「往台北」「往南」 | Direction phrases must be converted to actual origin/destination IDs |
| 「自強號」「對號」 | Train type filter applied client-side after rail_find_trains returns |

## Step-by-step flow

### Step 1: Parse the user query

Extract:
- **Origin station name** (zh or en)
- **Destination station name**
- **System** (TRA / THSR — required for `rail_find_trains`; metros use station-board tools instead)
- **Date** (default = today in Asia/Taipei)
- **Time anchor** (default = now; filter results to trains departing >= now)
- **Train type filter** (optional — 自強 / 莒光 / 區間 / etc.)

### Step 2: Resolve station IDs via `rail_search_stations`

If either station name is ambiguous (matches multiple stations) or you can't be sure of the system, call:

```
mcp__che-transport-mcp__rail_search_stations(query="<name>", system=<TRA|THSR|...>)
```

Show the user the matches and ask them to pick if >1 result.

### Step 3: Confirm before calling

Render the parsed form back to the user, e.g.:

> 即將呼叫 `rail_find_trains(from='1000', to='1070', system='THSR', date='2026-05-21')`，篩選 17:00 之後的班次。確認嗎？

Wait for "對 / 好 / yes / 確認". Don't preemptively call.

### Step 4: Call `rail_find_trains`

```
mcp__che-transport-mcp__rail_find_trains(from=<ID>, to=<ID>, system=<TRA|THSR>, date=YYYY-MM-DD)
```

### Step 5: Filter + format

- Filter trains where departure time >= time anchor
- Apply train-type filter if user requested
- Sort by departure time ascending
- Show top 3-5 to keep response readable

For each train show: train_no, 車種, 起站 dep, 迄站 arr, 行車時間, 票價（若有）.

### Step 6 (optional): Live delay check

If user explicitly asks "誤點" / "delayed" / "real-time" or the train they're picking departs within the next hour, additionally call:

```
mcp__che-transport-mcp__rail_status_train(train_no=<N>, system=<TRA|THSR>)
```

…and overlay delay info on the picked train.

## Empty result handling

If `rail_find_trains` returns `{"trains": []}`:

- Verify station IDs and date are valid (most likely cause: wrong system — e.g. asking THSR between two TRA-only stations)
- "Empty ≠ error" — say "今天該方向沒有班次" rather than treating as a tool failure
- Do NOT retry with different parameters without user input — that's scope creep

## When NOT to invoke

- Metro queries (`中山站下一班捷運往淡水`) — TRA/THSR `rail_find_trains` doesn't cover metro, use `rail_status_station` for metro arrivals
- Cross-system journeys (台北→台中→嘉義 mixed TRA+THSR) — out of scope for v0.2; tell user to query each leg
