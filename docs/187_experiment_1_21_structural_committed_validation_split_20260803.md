# Experiment 1-21 Structural / Committed Validation Split

## 목적

최종 6-core 실행을 시작하지 않고, artifact 구조 검증과 최종 커밋 검증의 순서를 분리했다. 이 문서는 실행 결과나 정책 효과를 판정하지 않는다.

## 변경한 계약

- `Assert-Exp121StructuralArtifacts`는 측정 산출물, raw stream의 개별 zero-byte 허용, JSON/JSONL parse, pool failure/coverage, capture metadata·byte count·runId·application 경로, 측정 타임라인만 검증한다.
- 구조 단계의 summary는 `FINALIZING/PENDING`이며 `artifactValidationCompletedAt`과 `finalizationCompletedAt`은 아직 없어도 된다.
- `Assert-Exp121CommittedArtifacts`는 final timestamp가 기록된 뒤 `COMPLETED/PASSED` summary와 전체 타임라인 순서를 검증한다.
- `COMPLETED` marker는 committed validation 통과 뒤에만 생성된다.
- stdout 또는 stderr 하나가 비어 있어도 허용한다. 단 두 stream의 합계와 `application.log`는 비어 있지 않아야 하며, metadata byte count와 실제 파일 길이가 같아야 한다.
- capture path는 run의 `application` 디렉터리 하위인지 separator boundary를 포함해 검증한다. `application-evil` 같은 prefix escape는 거부한다.
- 실패 시 `execution-summary.json`도 `EXECUTION_FAILED/FAILED`로 보존하며, 이미 생성된 collector coverage는 후속 capture/artifact 실패 때문에 덮어쓰지 않는다.

## 타임라인 계약

`collectorProcessStartedAt <= collectorFirstValidSampleAt <= coreInvocationStartedAt <= coreInvocationCompletedAt <= applicationLogCaptureStartedAt <= applicationLogCaptureCompletedAt <= collectorProcessCompletedAt`를 측정 단계에서 검증한다. 커밋 단계에서는 여기에 `artifactValidationCompletedAt <= finalizationCompletedAt`을 추가한다.

## 검증 결과

`test-experiment-1-21-finalization-contract.ps1`의 fixture 1~7을 실행했다.

| fixture | 확인 내용 | 결과 |
|---|---|---|
| 1 | final timestamp 없는 구조 단계 pass / committed fail | PASS |
| 2 | `COMPLETED/PASSED`와 final timestamp committed pass | PASS |
| 3 | premature completion fail | PASS |
| 4 | metadata byte mismatch fail | PASS |
| 5 | application path prefix escape fail | PASS |
| 6 | required artifact 누락 fail | PASS |
| 7 | committed pass 후 `COMPLETED` marker 생성 | PASS |

native log capture fixture와 기존 baseline/remediation no-load capture probe 및 Exp121 PLAN도 재검증한다. warm-up, load generator, k6, core performance run은 수행하지 않는다.

## 최종 상태

`EXP121_READY_FOR_SIX_CORE_RUNS`

이는 harness와 artifact contract가 준비됐다는 뜻이며, 성능 결과의 validity나 policy 효과를 의미하지 않는다.
