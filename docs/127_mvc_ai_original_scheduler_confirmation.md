# MVC AI Original Scheduler Confirmation

## Current execution

- Base HEAD: `ff35fcc301ea124ecf55905650c59eff26bfb08c`
- Runner: `experiment/scripts/run-mvc-ai-original-scheduler-confirmation.ps1 -Execute`
- Execution status: `STOPPED_INVALID`
- Failure phase: client process bootstrap, after startup gate and runtime contracts
- Failure: `node` was not available on PATH; PowerShell raised `CommandNotFoundException`.
- No HTTP request was started: `started=0`.

## Gate evidence

| Gate | Status |
|---|---|
| Image contract | PASS |
| Fresh project guard | PASS |
| Startup gate | PASS |
| MVC runtime contract | PASS |
| Mock runtime contract | PASS |
| Client accounting | FAIL / not reached |
| Scheduler contract | FAIL / not reached |
| Observer contract | FAIL / not reached |
| Final MVC state | PASS |
| Final mock state | PASS |
| Measurement validity | `false` |

Startup evidence: container started at `2026-08-11T15:35:43.724500139Z`, ready for load at `2026-08-11T15:36:03.9998530Z`, startup age `20275ms`, stable window `11278ms`.

The canonical MVC and mock image IDs were present locally and the run-specific tags matched them. The freshness guard found zero existing containers and zero existing project volumes. Runtime cleanup completed without restart or OOM.

## Workload disposition

- Performance workload: `NO`
- Node mission-load process: `NOT_STARTED`
- WebFlux: `NO`
- Application error counts: all requested exception/error patterns were `0`.
- No application outcome or performance classification is inferred.

The raw `measurement-validity.json` records `performanceWorkloadStarted=true` because the runner sets that flag immediately before attempting the Node invocation. The recorded `nodeExitCode=null`, `CommandNotFoundException`, and zero started requests establish that the Node process itself did not start; this run is therefore a setup failure, not a performance result.

The prior `$PSScriptRoot` initialization failure and bootstrap-only artifacts remain preserved under `experiment/results/bootstrap-history/MVC-AI-ORIGINAL-SCHED-001-pre-measurement`.

No automatic retry or code/config change was performed after this execution.
