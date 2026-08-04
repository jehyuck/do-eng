# Experiment 1-22 INVALID Closure

## 판정

RUN-20260804-EXP122-BASELINE-001은 `COLLECTOR_ENDED_EARLY`로 INVALID 종료한다. collector wall-clock 150초가 core invocation 완료 시각까지 도달하지 못해 `coversCoreEnd=false`가 되었다.

이는 system outcome이나 성능 결과가 아니라 필수 collector coverage 계약 실패다. RPS, HTTP status, latency, PrematureClose, pool/DB/container/mock 수치를 분석하지 않았다.

## 보존

- raw artifact를 수정·삭제·이동하지 않았다.
- raw path/size/SHA-256 inventory를 `backend/experiments/results/experiment-1-22/closure/raw-artifact-inventory.json`에 기록했다.
- measurement disposition을 `backend/experiments/results/experiment-1-22/closure/measurement-disposition.json`에 기록했다.
- 기존 Exp122 run ID를 재실행하지 않는다.
- 나머지 Exp122 5개 run은 실행하지 않는다.
- `RUNNING` marker 잔존 사실도 원본 상태로 보존한다.

## 정책

`policyDecision=NOT_RUN`, `eligibleForAggregate=false`, `finalExperimentState=INVALID`.
