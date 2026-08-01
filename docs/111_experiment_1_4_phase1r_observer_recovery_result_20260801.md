# Experiment 1-4 Phase 1-R — Observer Recovery Result

## Recovery status

`OBSERVER RECOVERED`

The DB monitor no longer uses synchronous child-process execution. No-load and
low-load scouts passed, and the VU200 scout completed without DB/container
observer timeout. The first post-recovery core had a transient stage/pool
collector issue before the single observer/retry correction; it remains
preserved as INVALID. The corrected replacement runs passed.

## Scout results

| Scout | Result | Key evidence |
|---|---|---|
| `RUN-20260801-EXP14R-SCOUT-A-001` | PASS | 12 container samples, 6 DB samples, 0 failures |
| `RUN-20260801-EXP14R-SCOUT-B-001` | PASS | corrected accounting/correctness PASS, DB failures 0 |
| `RUN-20260801-EXP14R-SCOUT-C-001` | PASS | VU200 corrected path, monitor exit 0, drain PASS |

## Valid core runs

| Run | 200 | 503 | 500 | Successful RPS | Completed RPS | Accepted p95 | DB/observer failures | Drain |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `RUN-20260801-EXP14R-BEFORE-003` | 11,568 | 9,067 | 1 | 110.1714 | 196.5333 | 5,160 ms | 0 | PASS |
| `RUN-20260801-EXP14R-BEFORE-004` | 12,680 | 7,980 | 0 | 120.7619 | 196.7619 | 3,162 ms | 0 | PASS |
| `RUN-20260801-EXP14R-BEFORE-005` | 11,838 | 8,819 | 0 | 112.7429 | 196.7333 | 3,876 ms | 0 | PASS |

All three passed corrected accounting, DB/storage consistency, observer
artifact and drain requirements. The earlier Phase 1 invalid runs remain
diagnostic and are not aggregated.
