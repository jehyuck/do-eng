# Experiment 1-19 core runner PLAN 결과

상태: `CORE_RUNNER_READY`

## 변경 파일

- `experiment/scripts/run-experiment-1-19-core.ps1`
- `experiment/scripts/run-experiment-1-19-six-core.ps1`
- `experiment/scripts/aggregate-experiment-1-19.js`

## PLAN 실행

`run-experiment-1-19-six-core.ps1 -ExecutionMode PLAN`을 실행했다.

- 정확한 여섯 run 순서의 command manifest 생성
- frozen application/mock image 존재 및 ID 확인
- Compose, helper, k6 fixture/script 경로 확인
- duplicate artifact guard와 required artifact contract 생성
- aggregator readiness: `INCOMPLETE`, decision: `NOT_RUN`

## side-effect 확인

- warm-up: 0
- k6: 0
- core: 0
- client-results 생성: 0
- completed core directory: 0
- `doeng-exp119-core` 컨테이너: 없음

PLAN artifact는 `backend/experiments/results/experiment-1-19/plan/`에 보존했다.

## 아직 없는 증거

실제 EXECUTE 경로의 health/reset/collector/warm-up/core/drain/verification 결과와 여섯 raw artifact는 아직 없다. 성능 또는 정책 효과도 판정하지 않았다.
