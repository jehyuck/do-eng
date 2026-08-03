# Experiment 1-22 Container Stop Evidence 및 Aggregator Identity Gate

## 목적

Experiment 1-22의 실행 하네스에서 컨테이너 종료 상태, native process exit, post-stop log capture, run/container identity를 실제 Evidence로 검증한다. 이번 작업은 성능 실행이 아니며 warm-up, k6, core load를 수행하지 않았다.

## 변경 범위

- `experiment-1-22-container-stop.ps1`: `docker inspect`의 실제 종료 코드와 전후 상태를 기록하고, 사전 상태 오류·컨테이너 소실·stop timeout을 별도 failure domain으로 보존한다.
- `experiment-1-22-native-log-capture.ps1`: .NET Process의 실제 exit code, timeout, termination confirmation, 원본 log byte 길이를 보존한다.
- `experiment-1-22-artifact-contract.ps1`: 필수 stop metadata, run/container identity, inspect/timeout/state 계약 및 timeline timestamp equality를 검증한다.
- `aggregate-experiment-1-22.js`: aggregator identity를 `Experiment 1-22`로 정정하고 동일 stop/capture 계약을 aggregate readiness에 적용한다.
- `test-experiment-1-22-post-stop-capture.ps1`: 정상 종료, 사전 종료 상태, 컨테이너 소실, non-zero stop, timeout, run ID/container ID mismatch, aggregator identity, large artifact fixture를 검증한다.

## 검증 결과

- PowerShell 6개 관련 스크립트 parse: PASS
- Node aggregator syntax check: PASS
- native process fixture A-L: PASS (`EXP122_NATIVE_PROCESS_FIXTURES_PASS`)
- BASELINE post-stop preflight: PASS
- REMEDIATION post-stop preflight: PASS
- PLAN artifact 생성: 6개 run 모두 생성
- preflight metadata: `inspectExitCodeBefore=0`, `inspectExitCodeAfter=0`, `stateBefore=running`, `stateAfter=exited`, `containerStillExists=true`, `stopStatus=APPLICATION_CONTAINER_STOPPED`
- final state: `EXP122_READY_FOR_SIX_CORE_RUNS`

## Identity / timeline 계약

- `stop.runId == run-config.runId`
- `stop.containerId == capture.containerId`
- `applicationStopStartedAt == stop.startedAt`
- `applicationStopCompletedAt == stop.completedAt`
- `applicationLogCaptureStartedAt == capture.startedAt`
- `applicationLogCaptureCompletedAt == capture.completedAt`
- aggregator output `experiment == Experiment 1-22`, `decisionState == NOT_RUN`

## 실행하지 않은 작업

- warm-up
- load generator / k6
- VU200 core
- 성능 결과 분석 또는 정책 판정
- 이미지, workload, pool, collector, resource tuning

## 최종 판정

`EXP122_READY_FOR_SIX_CORE_RUNS`

하네스와 Evidence 계약은 준비되었지만, 이는 measurement validity나 성능 결과를 의미하지 않는다.
