# Experiment 1-3 — Phase C Diagnostic Result

## Diagnostic runs

### RUN-20260801-EXP13-DIAG-001

Pre-execution/setup failure. The load driver was given the host root URL and
therefore requested `/` rather than `/game/face`; the run produced 404 responses
and no business-path evidence. It is retained as setup evidence and excluded
from all performance interpretation.

### RUN-20260801-EXP13-DIAG-002

Diagnostic-only WebFlux run under the frozen pool400/VU200/2CPU/3GiB contract.
The legacy verifier marked it invalid because the diagnostic produced controlled
system failures, but this does not invalidate the causal artifacts.

Observed client outcome:

- 11,885 scheduled/completed requests
- HTTP 200: 1,254
- HTTP 500: 6,300
- client abort: 4,331
- p50/p95/p99: 5,518 / 9,321 / 9,841 ms
- 113.19 requests/s

Runtime evidence:

- `PoolAcquirePendingLimitException`: 11,755 log occurrences
- `PrematureCloseException`: 455 occurrences
- Reactor Netty pool active maximum: 400
- sampled pending maximum: approximately 1,700
- targeted pool collector: 167 rows, 0 collection failures
- stage collector: 167 rows, 1 collection failure outside the measurement window
- DB stage failures: 0 in the stage counter snapshot
- load-stop/drain mock state: zero backlog at load stop and after drain

Stage counter snapshot near the end of measurement:

| Stage | Started | Succeeded | Failed | Cancelled | Max in-flight | Total duration |
|---|---:|---:|---:|---:|---:|---:|
| TOKEN | 11,885 | 6,836 | 4,050 | 1,000 | 1,162 | 39,176 s |
| AI | 6,836 | 3,562 | 2,333 | 941 | 830 | 30,126 s |
| STORAGE | 3,562 | 1,540 | 241 | 1,782 | 381 | 7,278 s |
| DB | 1,540 | 1,523 | 0 | 17 | 156 | 189 s |

The counters are aggregate observations, not per-request traces. Their purpose
is stage attribution, not a latency claim for every request.

## Static/runtime conclusion

The diagnostic directly correlates HTTP 500s with the shared Reactor Netty
provider reaching active 400 connections and the pending-acquire limit. Token
and AI failures dominate; DB did not show a corresponding failure signal. The
source audit also confirmed token, AI and HTTP storage clone a builder backed by
the same named `doeng-external` provider.

## Classification

**R5 — SHARED OUTBOUND RESOURCE INTERFERENCE: SUPPORTED.**

R1, R2, R3, R4, R6 and R7 were not directly established by this scout. The
legacy WebSocket detached subscriptions are not evidence for the current REST
`/game/face` path. Base64 remains a CPU candidate but was not shown to be
dominant.

## Selected first remediation

Move the existing fail-fast admission boundary from only the AI publisher to
the complete token→AI→storage→DB request publisher, preserving the existing
limit (320), 503 mapping, pool400, timeouts, and all resources.

Rejected alternatives: pool tuning, worker/CPU/memory changes, retry/fallback,
Base64 algorithm changes, scheduler sweep, MVC execution, or a second
remediation. Direct evidence did not justify any of those choices.
