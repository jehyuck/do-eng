# Experiment 1-6 - Scout Result

| Arm | Delay | Valid | HTTP200 | 503 | HTTP500 | Accepted p95 | Drain | Correctness |
|---|---:|---|---:|---:|---:|---:|---|---|
| AI1000 | 1,000 ms | VALID | 12,257 | 8,224 | 0 | 5,159 ms | PASS | PASS |
| AI500 | 500 ms | VALID | 13,090 | 7,411 | 2 | 5,005 ms | PASS | PASS |

Both scouts confirmed `FULL_PATH`, permit 320, the configured AI delay,
observer/accounting validity, and complete raw artifacts. The AI500 HTTP500
outcomes are preserved as system outcomes and did not invalidate the scout.
Scouts are excluded from the core aggregate.
