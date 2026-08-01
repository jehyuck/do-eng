# Run Ledger Addendum — Experiment 1-4 Phase 1-R

| Run | Type | Status | Note |
|---|---|---|---|
| `RUN-20260801-EXP14R-SCOUT-A-001` | no-load observer scout | VALID | async observer lifecycle; DB failures 0 |
| `RUN-20260801-EXP14R-SCOUT-B-001` | low-load integration scout | VALID | accounting, correctness and observer artifacts PASS |
| `RUN-20260801-EXP14R-SCOUT-C-001` | VU200 diagnostic scout | VALID | observer coverage and drain PASS |
| `RUN-20260801-EXP14R-BEFORE-001` | core replacement candidate | INVALID | legacy three-process stage collector failure |
| `RUN-20260801-EXP14R-BEFORE-002` | core replacement candidate | INVALID | one pool observer sample failed before retry correction |
| `RUN-20260801-EXP14R-BEFORE-003` | corrected BEFORE | VALID | included in aggregate |
| `RUN-20260801-EXP14R-BEFORE-004` | corrected BEFORE replacement | VALID | included in aggregate |
| `RUN-20260801-EXP14R-BEFORE-005` | corrected BEFORE replacement | VALID | included in aggregate |

All raw directories remain under `experiment/results/`. Invalid runs were not
deleted or aggregated.
