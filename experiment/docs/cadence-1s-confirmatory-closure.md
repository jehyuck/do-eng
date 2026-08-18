# 1s Cadence Confirmatory Closure

## Status

The 1-second cadence confirmatory cohort is closed without a performance measurement.

```text
FINAL_CLASSIFICATION: 1S_CONFIRMATORY_NOT_EXECUTED
BLOCKER: PRE_WORKLOAD_HARNESS_RUNTIME_BLOCKED
PERFORMANCE_RUN_COUNT: 0
WORKLOAD_STARTED: NO
```

No MVC1 workload request was started; WEBFLUX1, WEBFLUX2, MVC2, MVC3, and WEBFLUX3 were not executed.
This is not an invalid performance result because the performance workload never began.

## Frozen contract

The approved contract remained unchanged:

- VU: 160
- frame interval: 1000 ms
- duration: 105000 ms
- request timeout: 10000 ms
- AI: `true`, HTTP 200, 2000 ms
- storage: HTTP 200, 100 ms
- application: 2 CPU, 3 GiB
- HTTP pool: 400 connections / 400 pending
- DB pool: 10
- MVC Tomcat threads: 400
- JVM: Xms 512m / Xmx 2048m
- fixture: `image/arc.jpg`, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- expected request opportunities: 16800

## Provenance

The final execution harness commit was:

```text
38fe7bf56d31a17b63c59e0468356075e9569ee3
```

The canonical application base remained:

```text
d7448a74a1e45f6bf5a02e4624a3052ca86ac99a
```

Production source, `mission-load.js`, frozen config, and workload semantics were not changed.

## Pre-workload blocker chronology

The confirmatory preparation produced preserved pre-workload artifacts, including `PRELOAD-BLOCKED-01`, `PRELOAD-BLOCKED-02`, `PRELOAD-BLOCKED-03`, and `BUILD-DIAGNOSTIC-01`. State recovery artifacts `STATE-RECOVERY-01` and `STATE-RECOVERY-02` record exact user-set equivalence, zero dependency rows, exact cleanup, and zero remaining experiment-user rows.

The harness was minimally updated to resolve the Node executable to an absolute path and to record a no-workload spawn self-test. The final preflight passed source, frozen-contract, fixture, Node-resolution, and Node-spawn checks. During the subsequent MVC1 launch, the lower-level client process still failed before spawning the workload:

```text
Start-Process ... InvalidOperationException
actualRequestsStarted = 0
processSpawned = false
```

The final MVC1 failure evidence was preserved. No retry followed, and no later logical run was started.

## Evidence boundary

- 1-second performance result: unavailable.
- 1-second throughput, latency, stability, and framework comparison claims: not established.
- Exploratory 1-second matrix cells remain exploratory and are not promoted to confirmatory evidence.
- No result shopping or result substitution was performed.

## Existing canonical quantitative evidence

The validated SERVICE3S cohort remains the canonical quantitative Evidence for the existing comparison:

```text
Contract: VU160, AI delay 2s, 3s cadence, same application resource
Repetitions: MVC400 3 / WebFlux 3
WebFlux success median: 100%
WebFlux successful-RPS median: 51.457143
WebFlux p95 median: 3092 ms
MVC400 success median: 55.0762%
MVC400 successful-RPS median: 28.571429
MVC400 p95 median: 8339 ms
Successful-throughput median ratio: approximately 1.80x
```

The limitations already attached to the SERVICE3S evidence remain unchanged. These figures are not 1-second results.

## Final decision

The 1-second confirmatory experiment is closed as not executed. No further performance experiment is planned in this confirmatory sequence.

```text
1S PERFORMANCE CLAIM AVAILABLE: NO
EXPLORATORY 1S PROMOTED: NO
SERVICE3S EVIDENCE STATUS: PRESERVED
PRODUCTION SOURCE MODIFIED: NO
FINAL RETRY: NO
FURTHER PERFORMANCE EXPERIMENT: NONE
NEXT_ACTION: RESUME_CLAIM_REVIEW
```
