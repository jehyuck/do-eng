# Experiment 1-29 최종 3:3 비교 세트 Validity Audit

## 감사 범위

이번 문서는 Experiment 1-29의 최종 선택 6개 run이 동일한 실행 계약에서 수행되었고, 측정 계약을 충족하는지 확인한 기록이다. 성능 수치 비교와 lifecycle 정책 판정은 수행하지 않았다.

## Execution provenance

- branch: `experiment/doeng-fresh-first-lifecycle-policy`
- first-five execution HEAD: `8385854d1121e89b54d7969a28eb04b062ed29db`
- replacement execution HEAD: `8385854d1121e89b54d7969a28eb04b062ed29db`
- current HEAD: `8385854d1121e89b54d7969a28eb04b062ed29db`
- working tree: raw artifact와 허용된 harness 변경으로 dirty
- 허용된 변경: `RunIndex=004` 허용, aggregator selected-set 교체, BOM 호환, bounded observation 허용
- Production application, Mock, workload, pool, timeout, collector interval, compose topology, image는 변경하지 않았다.

## Selected set

Baseline 3개:

- `RUN-20260806-EXP129-BASELINE-001`
- `RUN-20260806-EXP129-BASELINE-002`
- `RUN-20260806-EXP129-BASELINE-003`

Remediation 3개:

- `RUN-20260806-EXP129-REMEDIATION-001`
- `RUN-20260806-EXP129-REMEDIATION-002`
- `RUN-20260806-EXP129-REMEDIATION-004`

제외 run:

- `RUN-20260806-EXP129-REMEDIATION-003`
- `EXECUTION_FAILED`
- `COLLECTOR_COVERAGE_FAILED`
- `maximumValidSampleGapMilliseconds=8861.206 > 8000`

선택 무결성: `PASS` (중복 0, 누락 0, 실패 run 선택 0)

## Configuration equivalence

6개 선택 run에서 다음이 일치한다.

- application image ID: `sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168`
- Mock image ID: `sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1`
- VU 200, duration 105초, frame 1초
- AI 2000ms, storage 100ms, timeout 10000ms
- app 2 CPU / 3GiB, HTTP pool 400, pending 800, DB pool 10, admission 320
- collector `CORE_BOUND_STOP_SIGNAL`, interval 1000ms, readiness/post-core/grace 10초, max duration 300초
- compose 파일 7개 및 SHA-256

조건 차이는 사전등록된 policy뿐이다.

- Baseline: FIFO / maxIdle 0ms / eviction 0ms
- Remediation: LIFO / maxIdle 3000ms / eviction 1000ms

Replacement equivalence: `PASS`

## Run validity

| Run | Measurement | Observation | Coverage | Lifecycle | Artifact | Cleanup |
|---|---|---|---|---|---|---|
| BASELINE-001 | VALID | COMPLETE | PASS | PASS | PASS | COMPLETED |
| BASELINE-002 | VALID | COMPLETE | PASS | PASS | PASS | COMPLETED |
| BASELINE-003 | VALID | COMPLETE | PASS | PASS | PASS | COMPLETED |
| REMEDIATION-001 | VALID | BOUNDED_TRANSIENT_LOSS | PASS | PASS | PASS | COMPLETED |
| REMEDIATION-002 | VALID | COMPLETE | PASS | PASS | PASS | COMPLETED |
| REMEDIATION-004 | VALID | COMPLETE | PASS | PASS | PASS | COMPLETED |

`REMEDIATION-001`의 bounded loss는 failures=1, maxConsecutiveFailures=1, maximum gap=6660.542ms, invalid JSONL=0으로 사전 계약 범위 안이다.

모든 선택 run은 core start/end coverage, timestamp monotonicity, first covering sample identity, lifecycle stop signal 및 process exit code 조건을 충족했다. timeline도 6개 모두 단조 증가하고 필수 timestamp가 존재한다.

## Artifact preservation

- 필수 artifact 누락: 없음
- JSON parse 오류: 없음
- 선택 raw artifact 수정: 없음
- 제외 raw artifact 수정: 없음
- 선택 artifact SHA-256 inventory: [selected-run-sha256.json](../backend/experiments/results/experiment-1-29/validity-audit-20260806/selected-run-sha256.json)
- 선택 manifest: [selected-run-manifest.json](../backend/experiments/results/experiment-1-29/validity-audit-20260806/selected-run-manifest.json)
- 구조화 감사 결과: [validity-audit-result.json](../backend/experiments/results/experiment-1-29/validity-audit-20260806/validity-audit-result.json)

## Limitation

replacement 실행은 동일 committed HEAD에서 수행됐지만 `RunIndex=004` 허용을 위한 harness 변경이 working tree에 반영된 상태였다. 이 dirty working-tree 상태 자체가 raw artifact에 독립적으로 기록되지는 않는다. 따라서 최종 분류는 `VALID_WITH_LIMITATION`으로 한다.

이 limitation은 production behavior, workload, collector 측정 계약 또는 image identity의 불일치를 의미하지 않는다.

## Decision

```text
EXP129_FINAL_SET_VALID_WITH_LIMITATION
EXP129_AGGREGATE_AUTHORIZED
REMAINING_LOAD_EXECUTIONS=0
PERFORMANCE_ANALYSIS=NOT_RUN
POLICY_DECISION=NOT_RUN
```
