## Why

Stage 3c-ii is the unified RAPTOR core — the engine that will eventually subsume the five pairwise-composing routers and enable ≥2-transfer journeys the current tools cannot express. This was deferred through 3a/3b/3c-i as demand-gated; the user has now chosen to build it (option C, the full unified core).

The honest framing carried forward into this work: there is **no demonstrated ≥2-transfer demand yet**, and RAPTOR adds **reachable journeys, not accuracy** — metro/bus remain headway-only (`E[wait]=headway/2`), so the core will be exactly as precise as today, just able to chain more legs. The justification for building now is the user's explicit direction, not a data-driven trigger; this is recorded so the decision stays auditable.

A five-tool rewrite is only defensible if it is **behavior-preserving and incremental**. The five shipped tools have frozen, tested behavioral contracts; those test fixtures become a **differential oracle**. This first increment (3c-ii.1) builds the core + a unified connection model and proves the core reproduces `transit_route`'s earliest-arrival journeys on `transit_route`'s own fixtures — **rewiring no tool**. Only once equivalence is proven do later increments migrate tools one at a time.

## What Changes

- New internal module: a unified time-dependent connection model spanning TRA (real per-train trips) + Taipei-Metro (headway-synthesized pseudo-trips across the service window) + curated cross-system transfers, plus a RAPTOR engine (round-based earliest-arrival) over it.
- A differential-equivalence harness: replay `transit_route`'s existing executor fixtures through the RAPTOR core and assert the journeys (legs, arrival, transfer count) match `transit_route`'s output within the documented tolerance for frequency legs.
- **No MCP tool is added, removed, or rewired** in this increment. `transit_route` and the other four tools keep their exact current behavior and code paths. The core is dead code from the tools' perspective until a later increment migrates them.

## Non-Goals

- Rewiring `transit_route` (or any of the five tools) to call the core — that is increment 3c-ii.2+, each gated by the migrated tool's frozen test suite.
- A `journey_plan` multi-transfer (≥2-transfer) tool — that capability falls out once the core is wired in; not this increment.
- Any accuracy improvement — the core inherits the headway/2 expected-wait ceiling; it reproduces, it does not refine.
- Bus integration into the core — this increment validates against `transit_route` (TRA+metro) only; bus connections come in a later increment.
- THSR / non-Taipei-metro coverage.

## Capabilities

### New Capabilities

- `raptor-core`: an internal unified time-dependent connection model + round-based RAPTOR earliest-arrival engine, validated to reproduce `transit_route`'s journeys on its existing fixtures, with no tool rewired.

### Modified Capabilities

(none)

## Impact

- Affected specs: `raptor-core` (new)
- Affected code:
  - New: Sources/CheTransportMCP/Tools/RaptorCore.swift (unified connection model + RAPTOR round engine)
  - New: Sources/CheTransportMCP/Tools/RaptorConnectionBuilder.swift (assemble TRA trips + metro headway pseudo-trips + interchange transfers into the unified model)
  - New: Tests/CheTransportMCPTests/RaptorCoreTests.swift (engine unit tests: single round, multi-round reachability, earliest-arrival dominance, headway pseudo-trip wait)
  - New: Tests/CheTransportMCPTests/RaptorTransitEquivalenceTests.swift (differential oracle: transit_route fixtures replayed through the core, journeys asserted equivalent)
  - Modified: CLAUDE.md (Stage 3c-ii roadmap: core landed internal, migration increments pending; tool count unchanged)
