# Experiment 1-5 Core Result

All three core runs were measurement-valid. System failures remain preserved
as outcomes, not invalidation reasons.

| Run | HTTP200 | 503 | HTTP500 | timeout | connection | successful RPS | 503 rate | accepted p95 | p99 | valid |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| FULLPATH352-001 | 8,709 | 10,508 | 0 | 296 | 1,009 | 82.9429 | 51.204% | 7,582 ms | 9,287 ms | VALID |
| FULLPATH352-002 | 11,418 | 8,309 | 2 | 296 | 577 | 108.7429 | 40.331% | 5,958 ms | 8,639 ms | VALID |
| FULLPATH352-003 | 13,193 | 7,451 | 0 | 21 | 0 | 125.6476 | 36.056% | 4,141 ms | 9,033 ms | VALID |

Every run had max permit in-use 352, permit leak 0, observer failure 0,
correctness PASS, and drain completion PASS. Pool exception text was not
present in the preserved artifacts. The two HTTP500 outcomes in run 002 are
system outcomes and prevent the safety gate from passing.
