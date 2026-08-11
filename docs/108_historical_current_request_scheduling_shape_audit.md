# Historical RUN-252 vs Current MVC Request-Scheduling Shape Audit

## Scope

This is a read-only comparison of existing artifacts. No workload, application, mock, or database was started; no source or load driver was changed.

Compared runs:

- Historical: `RUN-20260731-252`, raw closure bundle under `DoEng-WebFlux-Capacity-Closure/raw/RUN-20260731-252`.
- Current: `I1S-AI1S-M001`, raw artifacts under `experiment/results/I1S-AI1S-M001`.

Both runs use the recorded VU160/reconnect-ramp shape with 1,000 ms interval, 160 initial missions, staggered arrival, 3,000 ms activation interval, and 1,000 ms reconnect delay. AI delay differs (historical 2,000 ms; current 1,000 ms), so this document compares scheduling shape rather than latency or capacity.

## Current source lock

```text
CURRENT_SOURCE_LOCK: PASS
CURRENT_RUN: I1S-AI1S-M001
CANONICAL_INDEX: experiment/results/I1S-AI1S-PAIR001-artifact-index.json
CANONICAL_EVIDENCE_COMMIT: 4a19e9dcaaa8c0f34c35cf0cb08fe5443fcd20bf
started: 16464
completed: 16464
http200: 60
timeout: 16404
connectionError: 0
trueResponses: 60
successRate: 0.3644%
successfulRps: 0.571429
totalRps: 156.8
maxInFlight: 1615
```

All current values in this audit come from `experiment/results/I1S-AI1S-M001/**` and the canonical pair index. `I1S-AI1S-MVC-DIAG001`, `I1S-AI1S-MVC-JFR001`, and `I1S-AI1S-MVC-JFR002` are not used as current-run substitutes.

## Provenance and available fields

The current `experiment/load/mission-load.js` SHA-256 is:

`f3a6eb36798a57ce408de85e5420f65273bb5c2684bc02618822c4c78095619b`.

The recorded historical workload SHA-256 is:

`0e4aa35004f9a2da4b39f59147d523f8a7405aac2e56380bfeef4f2284daf218`.

The historical `client-results.json` request records do not contain `requestStartedAt` or `completedAt`; the current records do. Therefore historical per-request interval, exact first-user spread, and exact per-user overlap are `UNKNOWN`, while historical global start shape is available from `client-progress.jsonl`.

## Global arrival and first 10 seconds

All offsets below use each run's first `client-progress.jsonl` sample as T0. Progress is sampled about once per second, so these are sample-bounded observations, not exact event timestamps.

| Offset | Historical scheduled/started | Historical completed | Historical in-flight | Current scheduled/started | Current completed | Current in-flight |
|---:|---:|---:|---:|---:|---:|---:|
| T+1s | 160 | 0 | 160 | 54 | 0 | 54 |
| T+2s | 320 | 0 | 320 | 161 | 0 | 161 |
| T+3s | 480 | 53 | 427 | 321 | 0 | 321 |
| T+4s | 587 | 241 | 346 | 481 | 0 | 481 |
| T+5s | 747 | 437 | 310 | 641 | 0 | 641 |
| T+6s | 907 | 571 | 336 | 801 | 0 | 801 |
| T+7s | 1,051 | 733 | 318 | 961 | 0 | 961 |
| T+8s | 1,211 | 894 | 317 | 1,121 | 0 | 1,121 |
| T+9s | 1,371 | 1,031 | 340 | 1,281 | 0 | 1,281 |
| T+10s | 1,511 | 1,191 | 320 | 1,441 | 4 | 1,437 |

Historical therefore reached the full 160-request initial cohort by the first one-second sample. Current ramped entry was visibly distributed across the first three samples: 54, then 161 cumulative, then 321 cumulative. This is an observed scheduling-shape difference; it is not inferred from the configuration label alone.

The first ten-second progress totals are approximately 1,511 historical versus 1,441 current. The current run nonetheless accumulated much greater in-flight work because almost no requests completed before the timeout horizon. That response difference is not itself a scheduler measurement.

## Initial-user scheduling

Historical exact per-user first-start timestamps are unavailable. The historical progress sample at T+1.016s already reports 160 scheduled requests, so the initial cohort was fully scheduled within that sampling interval.

Current request timestamps provide an exact reconstructed first-start distribution for the 160 users:

```text
first user start offset: T+0.000s
last user start offset:  T+2.982s
spread:                  2,982 ms
p50 first-start offset:  1,484 ms
p95 first-start offset:  2,831 ms
```

The current request records show `activatedUsersAtSchedule` progressing through 1, 55, 109, and 160 for the first user's successive requests, which is consistent with staggered initial entry. Historical records instead show the first request cohort carrying `activatedUsersAtSchedule=160`, while `activeMissionUsersAtSchedule` varies by request; this field is not sufficient to recover historical wall-clock start offsets.

## Per-user interval and overlap

Current request timestamps, across 16,464 records carrying both start and completion timestamps, reconstruct the following:

```text
inter-request intervals:
min 996 ms
p50 1,007 ms
p95 1,024 ms
max 2,014 ms

per-user maximum overlap:
min 10
p50 10
p95 11
max 11
```

The canonical M001 client summary reports `maxInFlight=1615`, and direct interval reconstruction from the same timestamp-bearing M001 records also reaches 1,615. These values agree; no value from the diagnostic or JFR runs is used here.

Historical per-user interval and overlap distributions cannot be computed from the available `client-results.json`, because its request records lack the required timestamps. Historical global `maxInFlight=480` is valid as the recorded summary value, but `480 = 160 × 3` is not sufficient by itself to prove a hard per-user overlap cap of three.

## Response feedback and reconnect

Historical recorded 15,351 HTTP 200/`true` responses, so mission completion and subsequent reconnect activity are present in its request records. Canonical current `I1S-AI1S-M001` recorded 60 HTTP 200/`true` responses and 16,404 client timeouts; therefore only a small current successful-response subset is available for comparison with the historical feedback transition.

The current run's request records show no success-triggered VU exits in its accounting. This supports continued scheduling after failed/timeout requests, but it does not establish that the historical and current reconnect implementation is source-identical.

## Interpretation boundary

```text
REQUEST_SCHEDULING_SHAPE:
MATERIALLY_DIFFERENT

HISTORICAL_DISCREPANCY_CANDIDATE:
WORKLOAD_SCHEDULER_SEMANTICS_INCONCLUSIVE
```

The basis is the directly observed initial-arrival difference: historical had 160 scheduled by T+1.016s, whereas current reached 54 at T+1.003s, 161 at T+2.006s, and 321 at T+3.020s. The historical per-user timestamp evidence and historical load-driver source text are missing, so the scheduler discrepancy and its causal direction remain inconclusive; this does not establish that scheduler semantics alone caused the performance difference.

The early completion comparison points in the opposite direction for a scheduler-only explanation of the current collapse: at the first progress sample at or after T+10s, historical had 1,511 starts and 1,191 completions, while current had 1,441 starts and only 4 completions. This supports an early completion discrepancy and moves the causal focus toward per-request processing/runtime behavior rather than arrival scheduling alone.

```text
HISTORICAL_FIRST_START_SPREAD_MS: NOT_AVAILABLE; initial cohort <= 1,016 ms by progress sampling
CURRENT_FIRST_START_SPREAD_MS: 2,982
HISTORICAL_GLOBAL_PEAK_INFLIGHT: 480
CURRENT_GLOBAL_PEAK_INFLIGHT: 1615 summary and reconstruction
HISTORICAL_PER_USER_MAX_OVERLAP: UNKNOWN
CURRENT_PER_USER_MAX_OVERLAP: min 10 / p50 10 / p95 11 / max 11
HISTORICAL_INTERVAL_P50: UNKNOWN
CURRENT_INTERVAL_P50: 1,007 ms
HISTORICAL_FIRST_10S_STARTED: 1,511 at T+10.093s sample
CURRENT_FIRST_10S_STARTED: 1,441 at T+10.073s sample
HISTORICAL_FIRST_10S_PEAK_INFLIGHT: 340 at T+9.080s sample
CURRENT_FIRST_10S_PEAK_INFLIGHT: 1,437 at T+10.073s sample
HISTORICAL_FIRST_10S_COMPLETED: 1,191 at T+10.093s sample
CURRENT_FIRST_10S_COMPLETED: 4 at T+10.073s sample
EARLY_COMPLETION_DISCREPANCY: SUPPORTED
SCHEDULER_CAUSAL_DIRECTION: DOES_NOT_SUPPORT_CURRENT_COLLAPSE
PERFORMANCE_LOAD_EXECUTED: NO
PRODUCTION_CODE_CHANGED: NO
LOAD_DRIVER_CHANGED: NO
```

Raw artifacts remain unchanged. No claim is made that the historical scheduler source can be reconstructed line-by-line from the available evidence.
