# Run Ledger Addendum — Experiment 1-4 Phase 2

| Run | Type | Status | Note |
|---|---|---|---|
| `RUN-20260801-EXP14-AFTER-SCOUT-001` | diagnostic scout | VALID | per-outbound mode, accounting/observer/correctness PASS |
| `RUN-20260801-EXP14-AFTER-001` | AFTER core | VALID | included; system HTTP500/timeout/connection errors preserved |
| `RUN-20260801-EXP14-AFTER-002` | AFTER core | VALID | included; system HTTP500/timeout/connection errors preserved |
| `RUN-20260801-EXP14-AFTER-003` | AFTER core | INVALID | observer phase-1 collector final failure; raw preserved |
| `RUN-20260801-EXP14-AFTER-004` | AFTER replacement | VALID | included; system outcomes preserved |

The final aggregate contains only AFTER-001, AFTER-002 and AFTER-004.
