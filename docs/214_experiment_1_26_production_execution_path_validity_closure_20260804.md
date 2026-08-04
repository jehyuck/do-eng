# Experiment 1-26 — Production Execution Path 및 Reliability Gate Closure

## Exp125 Closure

Exp125는 collector polling timeout 1회로 `INVALID / MEASUREMENT_EXECUTED_OBSERVER_COVERAGE_FAILED` 상태를 유지한다. 기존 run ID·raw·SHA-256 inventory·[docs/211](211_experiment_1_25_invalid_pool_collector_timeout_closure_20260804.md)는 변경하지 않았다.

## Exp126 Core Runner

`experiment/scripts/run-experiment-1-26-core.ps1`를 추가했다. Exp125 production runner의 execution semantics를 유지하면서 Experiment 1-26 identity, artifact root, compose project, collector script만 분리한다. 동일 run ID collision과 첫 실패 즉시 중단 ledger를 유지한다.

`run-experiment-1-26-six-core.ps1`는 PLAN/EXECUTE 모두 구현되어 있으며, PLAN은 6개 command manifest를 생성·검증한다. EXECUTE는 사전 고정 순서로 core runner만 호출하고 첫 실패 뒤 후속 run을 시작하지 않는다.

## Collector Validity Contract

collector summary는 `processExitCode`, `failures`, `maxConsecutiveFailures`, `skippedPolls`, `maximumValidSampleGapMilliseconds`, `stopSignalObserved`를 포함한다. Exp126 full aggregator는 `failures=0`, `maxConsecutiveFailures=0`, `skippedPolls=0`, maximum gap `<=6000ms`, core 전후 valid sample coverage를 검증한다.

HTTP 오류는 가능한 경우 `Exception.Response.StatusCode`에서 실제 status를 보존한다. 실패 row는 삭제하지 않는다.

## Probe 결과

- BASELINE: 300초 idle, FIFO/0/0, 294 samples, failures 0, maximum gap 1028.385ms
- REMEDIATION: 300초 idle, LIFO/3000/1000, 294 samples, failures 0, maximum gap 1028.009ms
- 두 probe 모두 warmup/k6/core = 0이며 성능 결과를 만들지 않았다.

## Fixture/PLAN 결과

- Z1~Z8 collector reliability fixture: PASS
- full six-run aggregator fixture 및 mutation rejection X10~X18: PASS
- six-core PLAN manifest 6개 생성·검증: PASS

## 최종 판정

`EXP126_READY_FOR_SIX_CORE_RUNS`

실제 warm-up, k6, core, 성능 분석, 정책 decision은 아직 수행하지 않았다.
