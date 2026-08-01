# DoEng Experiment 1-4 Phase 2 Final Result

## Phase status

- Experiment 1-3 safety evidence: PRESERVED
- Experiment 1-4 Phase 1-R BEFORE: PRESERVED
- Experiment 1-4 Phase 2: **CLOSED**
- Tuned WebFlux vs MVC400: NOT STARTED

## Result classification

**E — CONTROL INSUFFICIENT OR NEW BOTTLENECK**

The per-outbound implementation was measurement-valid and preserved permit
leak safety, but it did not satisfy the preregistered improvement targets:

- BEFORE median successful RPS: 112.7429
- AFTER median successful RPS: 31.5143
- BEFORE median 503 rate: 42.689%
- AFTER median 503 rate: 60.724%
- BEFORE accepted p95 median: 3,876 ms
- AFTER accepted p95 median: 9,165 ms

The first two AFTER runs also contained HTTP500/connection errors, so the
safety gate was not preserved. Stage counters show substantial rejection at
TOKEN, AI and STORAGE; this is evidence of a new stage-level overload shape,
not proof that one specific stage is the sole root cause.

## What was proved

- A shared 320 permit can be held only around actual outbound WebClient calls.
- Aggregate permit accounting remains leak-free and bounded.
- Stage-level admission outcomes can be observed.

## What was not proved

- Per-outbound holding improves capacity in this workload.
- WebFlux superiority over MVC.
- Production capacity or optimal permit allocation.

No further tuning, MVC comparison, VU sweep or Phase 2.1 remediation was run.
