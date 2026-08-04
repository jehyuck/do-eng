# Exp128 Load-stop 관측 계약 분리

## 목적

기존 Exp128 실패에서 load-stop mock snapshot timeout을 성능 결과가 아닌 관측 상태로 보존하면서, drain 자료의 구조적 완전성을 독립적으로 검증한다. 이번 변경은 production application, mock 동작, workload, timeout, collector 측정 항목을 변경하지 않는다.

## 계약

- load-stop snapshot은 최초 1회만 호출한다. retry나 t0 대체값을 사용하지 않는다.
- `ok=true`이고 metrics가 있으면 `OBSERVED`이며 정확한 end-of-load backlog를 사용할 수 있다.
- `ok=false,error=timeout`이면 `TIMEOUT_RECORDED`로서 유효한 관측 기록이지만 정확한 t0 backlog는 사용할 수 없다. `endOfLoadInFlight`는 null이다.
- drain은 load-stop 1행과 drain sample N행을 포함한다. phase/sample 순서, timestamp/elapsedMs 단조성, 각 drain sample의 `ok=true`와 non-null metrics, summary의 initial/terminal identity를 검증한다.
- `drainCompleted=false` 또는 remaining backlog는 measurement invalid가 아니라 system outcome으로 보존한다.

## 구현 범위

`experiment-1-28-load-stop-contract.ps1`가 계약 필드를 계산하고, smoke verification은 `measurementEvidence.loadStopSnapshot`과 drain 검증 상태를 기록한다. 기존 assertion 이름 `loadStopAndDrainArtifactsPresent`는 유지한다.

`test-experiment-1-28-load-stop-contract.ps1`의 D1–D5 회귀 fixture는 observed, timeout-recorded, bad drain, missing artifact, incomplete drain을 각각 검증한다.

## 단일 diagnostic

정적 검증 후 `RUN-20260804-EXP128-BASELINE-001-DRAIN-CONTRACT`만 실행한다. 이 run은 aggregate에 포함하지 않으며, 성능 분석·정책 판정·Six-Core 실행은 별도 승인 없이는 수행하지 않는다.
