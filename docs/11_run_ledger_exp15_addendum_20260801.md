# Run Ledger Addendum - Experiment 1-5

| Run | Type | Status | Aggregate | Note |
|---|---|---|---|---|
| `RUN-20260801-EXP15-FULLPATH352-SCOUT-001` | diagnostic scout | VALID | excluded | config/accounting/observer/correctness/drain pass |
| `RUN-20260801-EXP15-FULLPATH352-001` | core | VALID | included | system timeout/connection outcomes preserved |
| `RUN-20260801-EXP15-FULLPATH352-002` | core | VALID | included | HTTP500=2 preserved as system outcome |
| `RUN-20260801-EXP15-FULLPATH352-003` | core | VALID | included | no HTTP500; all validity gates pass |

Raw artifacts are preserved under `experiment/results/` using the run IDs
above. No invalid replacement was required.
