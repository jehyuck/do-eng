# Experiment 1-22 Capture Timeline Single-Source Gate

## 범위

Experiment 1-22의 post-stop capture 시작 시각을 runner와 capture helper가 각각 생성하던 문제를 수정했다. 성능 실행, workload, image, collector, resource, pool 설정은 변경하지 않았다.

## 구현 사실

- `run-experiment-1-22-core.ps1`가 capture 직전에 `captureStartedAt`을 한 번 생성한다.
- 같은 값을 timeline의 `applicationLogCaptureStartedAt`과 `Invoke-Exp122PostStopLogCapture -StartedAt`에 전달한다.
- helper는 전달된 값을 재생성하지 않고 `docker-logs-capture.json.startedAt`에 그대로 기록한다.
- helper는 UTC ISO-8601 parse가 불가능하거나 미래 시각이면 process를 시작하지 않고 `APPLICATION_LOG_CAPTURE_STARTED_AT_INVALID`로 실패한다.
- capture `completedAt`은 실제 process 종료 또는 timeout 처리 후 helper가 생성한다.
- runner는 helper 반환값의 `startedAt`과 `completedAt`을 timeline에 반영한다.
- container stop timestamp 계약은 기존 helper 반환값을 계속 단일 원천으로 사용한다.

## 검증 결과

- PowerShell parse: PASS
- native process fixture: PASS
- single-source startedAt fixture: PASS
- timestamp mismatch rejection fixture: PASS
- invalid startedAt fixture: PASS
- timeout/non-zero/capture/stop identity fixtures: PASS
- BASELINE post-stop preflight: PASS
- REMEDIATION post-stop preflight: PASS
- six-core PLAN: 6개 crossover run 생성 PASS
- warm-up/k6/core: 0

## 계약 확인

```text
timeline.applicationStopStartedAt == stop.startedAt
timeline.applicationStopCompletedAt == stop.completedAt
timeline.applicationLogCaptureStartedAt == capture.startedAt
timeline.applicationLogCaptureCompletedAt == capture.completedAt
```

aggregator의 `Experiment 1-22`, run ID, container ID, stop/capture timestamp identity 검증은 유지된다.

## 최종 상태

`EXP122_READY_FOR_SIX_CORE_RUNS`

이는 하네스 준비 상태이며 성능 측정 결과나 정책 판정을 의미하지 않는다.
