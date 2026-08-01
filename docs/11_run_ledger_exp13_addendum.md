# Run Ledger Addendum — Experiment 1-3 (2026-08-01)

| Run ID | Type | Status | Evidence |
|---|---|---|---|
| RUN-20260801-EXP13-DIAG-001 | WebFlux diagnostic setup | PRE-EXECUTION FAILURE | Runner used `/` instead of `/game/face`; 404-only load. Raw artifacts retained; not a performance result. |
| RUN-20260801-EXP13-DIAG-002 | WebFlux diagnostic scout | DIAGNOSTIC-ONLY | Correct endpoint; stage/pool collectors completed. 11,755 `PoolAcquirePendingLimitException`, pool active 400, sampled pending max ~1,700; core validity was not inferred from the legacy correctness assertion. |
| RUN-20260801-EXP13-CORE-001 | WebFlux remediation core | VALID | Controlled-admission mode; 451 HTTP200, 318 HTTP503, 0 uncontrolled failures; p95 4,157 ms; drain completed. |
| RUN-20260801-EXP13-CORE-002 | WebFlux remediation core | VALID | Controlled-admission mode; 430 HTTP200, 275 HTTP503, 0 uncontrolled failures; p95 3,734 ms; drain completed. |
| RUN-20260801-EXP13-CORE-003 | WebFlux remediation core | VALID | Controlled-admission mode; 419 HTTP200, 278 HTTP503, 0 uncontrolled failures; p95 3,733 ms; drain completed. |

The first remediation moved the existing admission boundary from the AI stage
to the complete token→AI→storage→DB path. Pool/worker/resource/load conditions
were unchanged. Raw artifacts are under `experiment/results/{Run ID}/`.
