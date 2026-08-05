# Exp136 Pool-1000 Sufficiency

## Contract

VU200, 105 seconds, 1-second interval, AI 2,000ms, Storage 100ms, request timeout 10 seconds, SHARED Pool-1000, pending 800, Admission OFF, Mock result=true, lifecycle and application observation disabled, identical canonical fixture/auth/accounting contract.

## Run validity

- `RUN-001`: primary-valid.
- `RUN-002`: raw request/resource/drain results preserved, but invalid for primary aggregation because the runner exited before post-run container inspection/log finalization.
- `RUN-003`: primary-valid.

Only 2 of the required 3 primary-valid runs were obtained.

## Primary-valid outcomes

| Run | HTTP 200 | Success rate | HTTP 500 | Timeout | Connection failure | p95 | p99 | Drain |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 001 | 134 | 0.66% | 8,325 | 11,770 | 138 | 9,129ms | 9,827ms | PASS |
| 003 | 289 | 1.44% | 3,236 | 15,265 | 1,212 | 9,489ms | 9,930ms | PASS |

The observed primary-valid runs do not meet the preregistered sufficiency thresholds. However, because the 3-run validity requirement was not met, this is not a closed sufficiency claim.

## Decision

`POOL1000 SUFFICIENCY INCONCLUSIVE`

No additional pool size, VU, timeout, resource, admission, retry, or instrumentation experiment is authorized by this closure.
