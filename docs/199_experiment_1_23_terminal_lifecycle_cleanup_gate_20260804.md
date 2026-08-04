# Experiment 1-23 Terminal Commit·Lifecycle·Cleanup·Aggregator 최종 Gate

## 기준 상태

- Exp122 closure는 변경하지 않았다.
- Exp123 warm-up, k6/load, core performance run은 수행하지 않았다.
- 현재 branch HEAD는 이번 gate 구현 후 별도 커밋으로 기록한다.

## 반영한 계약

- collector summary를 실제 종료 후 parse하고 `COLLECTOR_STOPPED_BY_SIGNAL`, `stopSignalObserved=true`, `failures=0`, process exit code 0을 모두 요구한다.
- lifecycle artifact에 summary status/failure/stop-signal 값을 함께 보존하고, 성공 시에만 `COLLECTOR_LIFECYCLE_PASSED`와 `failureType=null`을 기록한다.
- `Wait-Exp123CollectorCoversCoreEnd`가 반환한 timestamp를 coverage·lifecycle·timeline에 동일하게 기록한다.
- Exp123 full required artifact 목록, collector lifecycle/coverage, runtime provenance, stop/capture identity, raw byte count, timeline을 structural/committed gate에서 검증한다.
- runtime provenance에 run/condition, frozen image tag·ID, policy, collector readiness, Compose file별 SHA-256을 기록한다.
- timeline에 post-core sample, coverage confirmation, stop signal 시각을 포함하고 전체 순서를 검증한다.
- 정상 terminal 순서는 structural validation → validation timestamp → final summary 준비 → finalization timestamp → committed validation → Compose cleanup → cleanup 결과 기록 → final committed validation → `COMPLETED` marker다.
- 실패 시 `failure-summary.json`, `execution-summary.json`, `EXECUTION_FAILED`를 보존하며 cleanup 결과를 남긴다.
- six-core PLAN ledger는 started/completed/failed/warm-up/k6/core를 모두 0으로 기록하고, EXECUTE ledger는 실제 경로 존재 여부로 계산한다.

## 무부하 검증

- PowerShell·Node 정적 검사: 통과
- production-path fixture A~S: 통과
- BASELINE production probe: frozen image·full Compose·health·collector summary·cleanup 통과
- REMEDIATION production probe: frozen image·full Compose·health·collector summary·cleanup 통과
- six-core PLAN: `EXP123_PLAN_READY`, 모든 실행 카운트 0

## 판정

`EXP123_READY_FOR_SIX_CORE_RUNS`

이는 사전등록된 6-core 실행을 시작할 수 있는 harness 계약이 충족됐다는 뜻이다. 성능 결과, PrematureClose 비교, 정책 채택 여부는 아직 판정하지 않았다.

## 실행 금지 확인

이번 gate에서는 warm-up, k6/load, VU200 core, 성능 분석, 정책 결정, Exp122 raw/closure 수정, PR·merge·tag를 수행하지 않았다.
