# MVC AI Original Scheduler Confirmation

## Execution

- Base HEAD: `0cc3f1472e76a04de5b4cfecd3737b460b973bd2`
- Runner: `experiment/scripts/run-mvc-ai-original-scheduler-confirmation.ps1 -Execute`
- Run ID: `MVC-AI-ORIGINAL-SCHED-001`
- Execution status: `COMPLETE`
- Measurement validity: `VALID`
- Application classification: `COLLAPSE`
- WebFlux: `NO`

The prior Node bootstrap failure is preserved as historical provenance under:

- `experiment/results/bootstrap-history/MVC-AI-ORIGINAL-SCHED-001-node-recovery-before-pass`
- `experiment/results/bootstrap-history/MVC-AI-ORIGINAL-SCHED-001-bootstrap-pass`

The stale project volume was verified to belong to the expected Compose project, had zero attached containers, and was removed before the BootstrapOnly gate. No other volume was removed.

## Validity gates

| Gate | Status |
|---|---|
| Image contract | PASS |
| Fresh project guard | PASS |
| Node runtime contract | PASS |
| Startup gate | PASS |
| MVC runtime contract | PASS |
| Mock runtime contract | PASS |
| Client accounting contract | PASS |
| Scheduler contract | PASS |
| Observer contract | PASS |
| Final MVC state | PASS |
| Final mock state | PASS |
| Node exit code | `0` |
| Performance workload started | YES |
| Measurement validity | `true` |

Node runtime: `C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe`, version `v24.14.0`.

## Workload result

| Metric | Value |
|---|---:|
| Started | 7,276 |
| Completed | 7,276 |
| Successful (`HTTP_200_ACCEPTED`) | 1,085 |
| Timeout | 6,059 |
| Connection error | 0 |
| HTTP 500 | 132 |
| Success rate | 14.91% |
| Timeout rate | 83.27% |
| Total RPS | 121.267 |
| p50 | 8,496 ms |
| p95 | 9,837 ms |
| p99 | 9,974 ms |
| Max in-flight | 1,598 |
| Success-triggered reconnects | 446 |

All requests were completed or classified; unfinished requests were `0`. The result is classified as `COLLAPSE` under the registered classification because success was below 80%.

## Scheduler and observer evidence

- `loadScenario`: `reconnect-ramp`
- `arrivalMode`: `staggered`
- `activeMissions`: `160`
- `initialActiveUsers`: `160`
- `activationStepUsers`: `1`
- `activationIntervalMs`: `3000`
- `reconnectDelayMs`: `1000`
- `intervalMs`: `1000`
- `durationMs`: `60000`
- `requestTimeoutMs`: `10000`
- Success matcher: JSON path `ai.result`
- Fixture: `image/arc.jpg`, 265,745 bytes, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`

Observer maxima from the captured samples:

- Tomcat busy: `400`
- Tomcat queue: `1,844`
- HTTP active: `373`
- HTTP pending: `0`
- AI in-flight: `117`
- Storage in-flight: `0`
- Container restart: `0`
- OOMKilled: `false`

The mock drain completed after `10,038 ms`; terminal AI/storage in-flight values were both `0`. The observer artifact recorded readiness polling failures during load, but its contract remained valid and application/mock samples were captured.

## Interpretation boundary

`SCHEDULER_SEMANTICS_EFFECT: NOT_SUFFICIENT`

`IMMEDIATE_FIXED_SCHEDULER_CONFOUNDER: NOT_ESTABLISHED`

This execution establishes a valid result for the configured scheduler and records a collapse outcome. It does not by itself establish a low-level root cause or isolate the scheduler as causal.

No automatic rerun or additional workload was executed.

## Evidence provenance closure

An earlier documented result exists, but its raw artifact is unavailable. It is
non-canonical and is not used for quantitative conclusions.

The locally re-verifiable raw candidate is recorded in
`docs/128_mvc_ai_original_scheduler_evidence_manifest.md` with
`started=7,276`, `successful=1,085`, `timeout=6,059`, `connectionError=0`, and
`HTTP 500=132`. Both documented/raw candidates are classified as `COLLAPSE`,
but only the raw candidate is used as canonical evidence in this closure.

`VALID_MEASUREMENT_COUNT: 1`

`REGISTERED_ONE_RUN_CONTRACT: NOT_VERIFIABLE`

`SECOND_EXECUTION_TRIGGER: NOT_ESTABLISHED`

`SCHEDULER_SEMANTICS_EFFECT: NOT_SUFFICIENT`

`IMMEDIATE_FIXED_SCHEDULER_CONFOUNDER: NOT_ESTABLISHED`
