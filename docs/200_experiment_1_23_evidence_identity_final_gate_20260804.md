# Experiment 1-23 Evidence Identity 최종 Gate

## 범위

Exp122 closure와 frozen workload/resource/Compose 조건은 변경하지 않았다. Exp123 warm-up·k6·core 성능 실행도 수행하지 않았다.

## 반영 사항

- `New-Exp123CollectorCoverage`가 `Wait-Exp123CollectorCoversCoreEnd`의 실제 반환값을 입력받고, JSONL의 첫 valid sample 중 core 종료 이후 첫 sample과 일치하는지 검증한다.
- coverage·lifecycle·timeline의 `collectorFirstSampleCoveringCoreEndAt`를 동일 timestamp로 검증한다.
- `run-config.json` PLAN/EXECUTE manifest의 Compose 7개를 `{path, sha256}` 구조로 기록한다.
- runtime provenance에서 runDate, image tag·ID, policy, collector timestamps, Compose SHA-256을 현재 repository 파일과 exact 비교한다.
- container stop의 상태·timeout·exit code·inspect code·identity·timestamp를 검증한다.
- post-stop capture의 상태·timeout·exit code·status·경로 containment·stdout/stderr/combined 실제 byte 수를 검증한다.
- aggregator에 위 identity·provenance·stop/capture·cleanup 계약을 반영했다.
- six-core ledger에 실제 `warmupInvoked`, `coreInvoked`, `k6Invoked`를 기록하며 현재 runner 구조에서는 core invocation이 k6 invocation을 의미하도록 명시했다.

## 무부하 검증

- PowerShell/Node 정적 검사: 통과
- production fixture A~S 및 targeted fixture T1~T14: 통과
- BASELINE probe: full Compose·image/policy binding·health·collector summary·cleanup 통과
- REMEDIATION probe: full Compose·image/policy binding·health·collector summary·cleanup 통과
- six-core PLAN: Compose path/SHA, image, policy, workload, collector contract 기록; started/warm-up/core/k6 모두 0

## 판정

`EXP123_READY_FOR_SIX_CORE_RUNS`

이는 Evidence identity와 runner 계약이 6-core 실행 전 검증됐다는 의미다. 성능 결과나 정책 효과는 아직 생성하지 않았다.

## 미실행

실제 warm-up, k6, VU200 core, 성능 분석, 정책 결정, Exp122 raw/closure 수정은 수행하지 않았다.
