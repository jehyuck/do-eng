# Experiment 1-6 - Core Result

All six core runs were measurement-valid.

| Arm | Run | HTTP200 | 503 | HTTP500 | Timeout | Connection | Successful RPS | 503 rate | Accepted p95 | Accepted p99 | AI mean ms | Permit max | Leak | Valid |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| AI1000 | 001 | 14,315 | 6,234 | 0 | 103 | 0 | 136.3333 | 30.186% | 3,787 | 7,496 | 1,355.6 | 320 | 0 | VALID |
| AI500 | 001 | 15,177 | 5,402 | 0 | 48 | 0 | 144.5429 | 26.189% | 4,371 | 8,118 | 997.2 | 320 | 0 | VALID |
| AI1000 | 002 | 14,003 | 6,575 | 0 | 59 | 0 | 133.3619 | 31.860% | 4,351 | 8,737 | 1,387.2 | 320 | 0 | VALID |
| AI500 | 002 | 14,333 | 6,249 | 0 | 54 | 0 | 136.5048 | 30.282% | 4,503 | 8,336 | 1,056.2 | 320 | 0 | VALID |
| AI1000 | 003 | 14,529 | 6,076 | 0 | 21 | 0 | 138.3714 | 29.458% | 4,089 | 7,959 | 1,366.7 | 320 | 0 | VALID |
| AI500 | 003 | 14,435 | 6,166 | 0 | 47 | 0 | 137.4762 | 29.862% | 4,713 | 8,308 | 1,045.1 | 320 | 0 | VALID |

All runs had observer failure 0, correctness PASS, and 30-second drain PASS.
No `PoolAcquirePendingLimitException` text was found in the preserved core
artifacts. Controlled rejection and timeout/connection outcomes are retained
as system outcomes.

## Resource shape

Across the six runs, application container CPU peaks were approximately
212-218% of one CPU and memory peaks approximately 75-78% of the 3 GiB limit;
PIDs remained 33-34. These observations do not establish a unique host-level
root cause.
