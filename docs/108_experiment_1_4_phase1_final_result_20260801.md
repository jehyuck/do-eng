# Experiment 1-4 Phase 1 — Final Result

## Completion status

`PARTIAL — CORRECTED LOAD/ACCOUNTING IMPLEMENTED; BASELINE CLOSURE BLOCKED`

The measurement-only correction is implemented and tested. The client now
keeps VUs active for the full duration, classifies every completed request,
reports separate latency populations and checks accounting equations.

The Phase 1 baseline could not be closed because all three 200-VU core
attempts failed the frozen DB/container collector validity gate with
`spawnSync docker ETIMEDOUT`. Their raw artifacts remain in
`experiment/results/` and are not silently removed or aggregated.

## No claim

No BEFORE median/MAD, AFTER threshold, tuned implementation result or WebFlux
performance claim is produced. The next action requires an explicitly
approved observer-contract recovery; this task does not change that contract
or start Phase 2.
