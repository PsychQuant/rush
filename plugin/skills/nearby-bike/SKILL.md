---
name: nearby-bike
description: Find YouBike (1.0 + 2.0) stations near a location with live available-rent / available-return counts. Use when user says "我附近有 YouBike 嗎 / 哪裡有 ubike / 借車 / 還車 / 信義區誠品 youbike / 北車 youbike" or similar geographic bike queries. Walks user from landmark → coordinates → `bike_stations_nearby`, sorts by distance, surfaces available counts so user can pick a station with capacity.
allowed-tools:
  - AskUserQuestion
  - WebSearch
---

# nearby-bike — find YouBike near a location

Wraps `bike_stations_nearby` for the most common bike-share use case: "where's the closest YouBike with a bike to rent (or empty slot to return)?"

## NSQL discipline

Parse → confirm → call. The slippery part for bike queries is converting **landmark names to lat/lon coordinates**, since `bike_stations_nearby` takes geographic input not station names.

## Step-by-step flow

### Step 1: Parse the user query

Extract:
- **Location anchor** (landmark / address / explicit lat-lon)
- **City** (BikeCity code — Taipei / NewTaipei / Taoyuan / Taichung / Tainan / Kaohsiung / Hsinchu / HsinchuCounty / ChanghuaCounty / PingtungCounty / Chiayi / ChiayiCounty / MiaoliCounty / YilanCounty / Keelung)
- **Search radius** (default 500 m; clamp to [50, 3000])
- **Intent** — borrow (need `available_rent > 0`) or return (need `available_return > 0`)? Default = borrow.

### Step 2: Geocode landmark → lat/lon

If user gave coordinates directly, skip this step. Otherwise:

- For well-known landmarks (台北車站 / 101 / 西門町 / 高雄美麗島站 / 中正紀念堂 / 高鐵某站), you may already know coordinates.
- For ambiguous or less-famous addresses, use WebSearch with query like `"<landmark> latitude longitude"` to get coordinates from Wikipedia / Google Maps page snippets.
- Always **confirm the geocoded coordinates with the user before proceeding** — "誠品" matches dozens of locations across Taiwan.

### Step 3: Pick a city

Most landmarks map unambiguously to a city, but show your inferred BikeCity to the user and let them correct.

### Step 4: Confirm before calling

Render the parsed form, e.g.:

> 即將呼叫 `bike_stations_nearby(lat=25.0478, lon=121.5170, city='Taipei', radius_m=500)`（台北車站方圓 500 公尺）。確認嗎？

### Step 5: Call `bike_stations_nearby`

```
mcp__che-transport-mcp__bike_stations_nearby(lat=<float>, lon=<float>, city=<BikeCity>, radius_m=<int>)
```

### Step 6: Filter by intent

- **Borrow** (default): only show stations with `available_rent > 0` AND `service_status == 1` (營運中)
- **Return**: only show stations with `available_return > 0` AND `service_status == 1`
- Sort by `distance_m` ascending
- Show top 5 with: name_zh, distance_m, service_type (1.0 vs 2.0), available_rent / available_return

### Step 7 (optional): Empty radius expansion

If filtered result is empty:
1. **Confirm with user** before expanding — "500m 內沒有可借的 YouBike，要擴大到 1000m 嗎？"
2. Re-call with larger radius (capped at 3000m)
3. Do NOT silently expand — wastes their attention if they actually want to know "nothing close"

## Empty result handling

- Empty within max radius = legitimate result, present as "您附近沒有 YouBike 站點" not as an error
- City coverage uneven — TDX YouBike data spans ~15 cities but rural counties may return empty regardless
- Service type filter: most users don't care 1.0 vs 2.0 — surface it as info but don't require user to specify
