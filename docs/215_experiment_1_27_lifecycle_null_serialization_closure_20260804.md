# Experiment 1-27 — Lifecycle Null Serialization Closure

## Exp126 closure

Exp126은 `INVALID / ARTIFACT_LIFECYCLE_VALIDATION_FAILED`로 보존한다. 원인은 lifecycle writer가 성공 상태의 `failureType` 빈 문자열을 JSON에 기록하여 validator의 `null` 계약과 불일치한 것이다. Exp126 run ID와 raw artifact는 재사용하지 않는다.

## Exp127 변경

Exp126 production runner를 정적 Exp127 runner로 복사하고 identity만 변경했다. collector, workload, resource, policy, artifact contract, crossover order는 변경하지 않았다. lifecycle JSON 작성 직전에 `failureType`이 공백이면 `$null`로 정규화한다. 실제 failure text는 그대로 보존한다.

## Regression

- L1 null input: PASS
- L2 blank input normalizes to JSON null: PASS
- L3 real failure text preserved: PASS
- L4 blank string written directly is rejected by validator: PASS
- finalization fixture: PASS
- Exp127 six-core PLAN: 6 manifests, zero started/warmup/core/k6, `NOT_RUN`

## Execution boundary

Regression과 PLAN이 통과한 뒤 Exp127 six-core EXECUTE를 수행한다. 첫 harness/validity failure 시 즉시 중단하며 성능 결과나 policy decision은 실행 단계에서 해석하지 않는다.
