# Experiment 1-4 Phase 2 — AFTER Result

## Valid runs

| Run | 200 | 503 | HTTP500 | Timeout | Connection error | Successful RPS | 503 rate | Accepted p95 | Valid |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `RUN-20260801-EXP14-AFTER-001` | 3,309 | 11,928 | 39 | 1,487 | 2,880 | 31.5143 | 60.724% | 9,165 ms | VALID |
| `RUN-20260801-EXP14-AFTER-002` | 1,877 | 8,761 | 24 | 2,742 | 4,438 | 17.8762 | 49.103% | 9,762 ms | VALID |
| `RUN-20260801-EXP14-AFTER-004` | 7,667 | 12,875 | 0 | 61 | 0 | 73.0190 | 62.491% | 6,612 ms | VALID |

All three are measurement-valid. High errors and latency are preserved as
system outcomes, not invalidation reasons.

## Stage admission

| Run | Stage | Acquired | Rejected | Released |
|---|---|---:|---:|---:|
| AFTER-001 | TOKEN / AI / STORAGE | 8,154 / 5,655 / 3,920 | 8,689 / 2,379 / 1,250 | 8,154 / 5,655 / 3,920 |
| AFTER-002 | TOKEN / AI / STORAGE | 6,330 / 4,451 / 2,755 | 7,154 / 1,640 / 857 | 6,330 / 4,451 / 2,755 |
| AFTER-004 | TOKEN / AI / STORAGE | 12,578 / 9,781 / 7,806 | 8,105 / 2,797 / 1,975 | 12,578 / 9,781 / 7,806 |

Aggregate max in-use was 320 and permit leak was 0 in every run. DB/storage
correctness and drain passed.
