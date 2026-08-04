# Experiment 1-28 Cleanup Finalization Closure 및 Experiment 1-29 실행 준비

## Exp128 closure

`RUN-20260805-EXP128-BASELINE-001`은 workload, measurement, collector, capture, artifact copy까지 완료했고 measurement validity는 VALID이었다. 다만 cleanup 이후 빈 `docker compose ps -q` 결과에 `.Trim()`을 직접 호출하면서 `null-valued expression`이 발생했다.

원본 artifact와 `EXECUTION_FAILED` terminal marker는 변경하지 않는다. Exp128은 다음 상태로 보존한다.

- `measurementValidity = VALID`
- `artifactContentValidation = 확인된 raw artifact는 PASS`
- `cleanupResult = FAILED_DURING_EMPTY_STATE_CHECK`
- `failureDomain = CLEANUP_FINALIZATION`
- `eligibleForAggregate = false`
- 성능 분석·정책 판정: 미수행

## Exp129 changes

Exp128 runner를 identity만 변경한 새 runner로 복사하고, cleanup finalization을 null-safe하게 분리했다.

- `docker compose down` 종료 코드 확인
- `ps -q` 결과를 배열로 정규화
- state query 종료 코드 확인
- 빈 배열과 `$null`을 정상적인 zero remaining-container 상태로 처리
- 실제 container ID가 남으면 `CLEANUP_CONTAINERS_REMAIN`
- artifact validation과 cleanup 상태를 별도 flag로 기록
- cleanup 단계 실패를 `CLEANUP_FINALIZATION`으로 분류
- Exp129 표준 run만 허용: `BASELINE/REMEDIATION × 001/002/003`

Production application, mock, image, compose topology, workload, collector, lifecycle policy, artifact schema, load-stop/drain contract는 변경하지 않았다.

## Regression

`test-experiment-1-29-cleanup-finalization.ps1`에서 C1–C6을 검증한다. 정식 Six-Core 실행 전 PowerShell/JavaScript syntax, 기존 P1–P6·D1–D5·L1–L4와 Exp129 PLAN을 확인한다.
