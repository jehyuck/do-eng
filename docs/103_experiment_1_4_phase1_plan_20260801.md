# Experiment 1-4 Phase 1 — Corrected BEFORE Plan

Status: APPROVED FOR PHASE 1 IMPLEMENTATION/VALIDATION ONLY

## Purpose

Correct load-generation and accounting semantics while preserving the
Experiment 1-3 full-path admission behavior. Then establish three VALID
corrected BEFORE runs for the later per-outbound-call comparison.

## Single scope of change

Measurement contract only:

- VUs continue iterating for the complete 105-second measurement window.
- HTTP200 no longer terminates a VU.
- HTTP503/500/timeout/abort do not trigger immediate retry; normal 1-second
  pacing remains.
- Each request receives exactly one classified outcome.
- Successful, controlled-rejection, uncontrolled, client and all-completed
  latency populations are reported separately.
- Admission/stage counters are collected per run.

No application business path, admission budget/scope, pool, resource, timeout,
mock delay, fixture, auth, DB or MVC condition changes.

## Frozen BEFORE contract

Corrected WebFlux, full-path gate enabled, budget 320, zero-wait fail-fast,
controlled 503, pool400, DB pool10, CPU2, memory3GiB, VU200, AI2s,
storage100ms, frame/reconnect1s, duration105s, client timeout10s, same fixture,
auth, DB/storage and completion semantics, fresh JVM per core run.

## Run sequence

1. Source/load accounting audit.
2. Implement measurement-only correction and tests.
3. JDK11/Gradle/build gate.
4. Fresh runtime preflight.
5. Diagnostic scout (not aggregate).
6. Three corrected BEFORE VALID core runs:
   `RUN-20260801-EXP14-BEFORE-001..003`.
7. Freeze capacity baseline and AFTER thresholds.

Invalid instrumentation runs are replaced individually; system outcomes remain
valid outcomes. No Phase 2 implementation or tuned comparison occurs here.

## Validity invariants

```text
classified total = HTTP200 + HTTP503 + HTTP500 + other client/server outcomes
started = classified completed + unfinished at load stop
acquired = released + final in-use
final in-use = 0 and permit leak = 0 after drain
max in-use <= 320
```

Required evidence includes accepted-only p50/p95/p99, controlled-503 latency,
per-run admission counts, aggregate stage counters, pool/container/DB/mock
artifacts, load-stop/drain and correctness/no-side-effect verification.

## Stop rules

After three VALID BEFORE runs, calculate median/min/max and variability. Freeze
the material-improvement thresholds before any AFTER code change:

- HTTP200 throughput improvement: `max(10%, 2 × MAD/median)`
- controlled-503 reduction: `max(5 percentage points, 2 × MAD)`
- accepted p95 guard: AFTER median <= BEFORE median × 1.10

No additional run, pool/worker/resource tuning or Phase 2 correction is allowed
after the baseline freeze in this task.
