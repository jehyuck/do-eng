# Experiment 1-28 — Production Lifecycle Null 정규화 Closure

## Exp127 Closure

Experiment 1-27은 `INVALID`로 보존한다.

- classification: `MEASUREMENT_EXECUTED_ARTIFACT_LIFECYCLE_VALIDATION_FAILED`
- failureDomain: `ARTIFACT_FINALIZATION`
- failureType: `COLLECTOR_LIFECYCLE_NULL_SERIALIZATION_MISMATCH`
- eligibleForAggregate: `false`
- remaining runs: `NOT_STARTED`
- policyDecision: `NOT_RUN`

Exp127의 raw artifact는 수정하거나 삭제하지 않았다.

## Exp128 Production Source

Exp127 production runner를 정적으로 복사하고 identity만 Exp128로 변경했다. workload, image, compose 7개, collector, policy, artifact contract, crossover order는 유지했다.

Production runner:

`experiment/scripts/run-experiment-1-28-core.ps1`

검증 결과:

- `failureType` 빈 값의 `$null` 정규화 코드: 1개
- 정규화 코드가 lifecycle `W $life` 호출보다 앞에 존재: 확인
- lifecycle `W $life` 호출: 1회
- Exp127 identity 잔존: 없음
- Exp126 collector implementation 사용: 확인

정규화는 실제 failure text를 변경하지 않고, 성공 lifecycle에서만 빈 문자열을 JSON `null`로 바꾼다.

## Regression

`test-experiment-1-28-lifecycle-null-serialization.ps1` 결과:

- L1 null input → JSON `null`: PASS
- L2 blank input → JSON `null`: PASS
- L3 real failure text 보존: PASS
- L4 직접 기록된 빈 문자열 → validator rejection: PASS

결과: `EXP128_LIFECYCLE_NULL_REGRESSION_PASS`

## Six-Core PLAN

`run-experiment-1-28-six-core.ps1 -RunDate 20260804 -ExecutionMode PLAN` 결과:

- manifest count: 6
- started/warmup/core/k6: 0
- executionStatus: `NOT_RUN`
- policyDecision: `NOT_RUN`

결과: `EXP128_PLAN_READY`

## Execution Boundary

이 문서는 production lifecycle 정합화와 실행 전 게이트만 기록한다. six-core 실행 전에는 성능 해석이나 정책 판정을 하지 않는다. 실제 실행은 clean execution clone에서 사전등록된 명령을 한 번 수행하며, 첫 harness/validity 실패 시 즉시 중단한다.
