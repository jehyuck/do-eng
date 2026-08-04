# Experiment 1-23 Runtime·Collector·Artifact Contract Correction

## 판정

기존 Exp123 readiness는 reject로 재분류했다. 이전 구현은 manifest-only policy, fixed `Start-Sleep` readiness, 추정 timestamp, container stop/capture/validation 누락이 있었기 때문이다. Exp122 closure와 raw inventory는 변경하지 않았다.

## 보강한 구현

- frozen application/mock image ID gate
- Exp122와 동일한 Compose override stack
- condition별 실제 process environment binding 및 finally 복원
- `Wait-Exp123CollectorReady`의 process/JSONL/JSON/timestamp/failure 검증
- core 시작·종료 timestamp의 disk 기록
- 실제 post-core covering sample gate
- atomic stop signal과 collector exit/summary 검증
- 실제 sample 기반 collector lifecycle Evidence
- pool staging→target artifact copy
- Exp122 stop/capture helper 계약 재사용
- runtime provenance·failure summary·terminal marker
- structural/committed validation 경로
- aggregator의 lifecycle/coverage/terminal/artifact 계약
- six-core ledger의 PLAN/EXECUTE count 분리

## 검증

- PowerShell parse: PASS
- Node syntax: PASS
- Fixture A–N: PASS
- BASELINE collector-only probe: `CORE_BOUND_COLLECTOR_PROBE_READY`
- REMEDIATION collector-only probe: `CORE_BOUND_COLLECTOR_PROBE_READY`
- Exp123 PLAN 6개: PASS
- warm-up/k6/core: 0

## 최종 상태

`EXP123_READY_FOR_SIX_CORE_RUNS`

실제 Exp123 core는 실행하지 않았다.
