# Run Ledger Addendum — Experiment 1-4 Phase 1 (2026-08-01)

| Run | Type | Result | Reason / preservation |
|---|---|---|---|
| RUN-20260801-EXP14-SCOUT-001 | setup | PRE-EXECUTION FAILURE | Health checked after a fixed 8s wait; application startup exceeded it. No load entered. |
| RUN-20260801-EXP14-SCOUT-002 | diagnostic | INVALID | Corrected client path ran, but 200-VU scout had DB monitor `spawnSync docker ETIMEDOUT` failures; warm-up artifacts retained. |
| RUN-20260801-EXP14-SCOUT-003 | diagnostic | INVALID | 20-VU corrected warm-up valid and client accounting passed; DB monitor had 21 collection failures during 200-VU run. |
| RUN-20260801-EXP14-BEFORE-001 | corrected BEFORE attempt | INVALID | Client raw/accounting preserved; DB monitor had 41 `spawnSync docker ETIMEDOUT` failures. |
| RUN-20260801-EXP14-BEFORE-002 | corrected BEFORE attempt | INVALID | Client raw/accounting preserved; DB monitor had 39 `spawnSync docker ETIMEDOUT` failures. |
| RUN-20260801-EXP14-BEFORE-003 | corrected BEFORE attempt | INVALID | Client raw/accounting preserved; DB monitor had 21 `spawnSync docker ETIMEDOUT` failures. |

No run above is included in a final BEFORE aggregate. Existing Experiment 1-3
results and earlier Phase 1 documents remain unchanged.
