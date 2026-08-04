# Experiment 1-23 Aggregator·Manifest·Coverage Single-Path Closure

## 범위

Exp122 closure와 Exp123의 조건·frozen image·Compose stack·collector lifecycle은 변경하지 않았다. 실제 warm-up·k6·core 성능 실행도 하지 않았다.

## 반영 사항

- core runner가 Compose descriptor `{path, sha256}`를 먼저 생성하고 같은 canonical manifest를 PLAN과 EXECUTE에 사용한다.
- six-core PLAN runner가 JSON을 다시 덮어쓰지 않고, 개별 core PLAN 결과의 canonical descriptor를 검증·보존한다.
- coverage artifact는 named parameter와 명시적 `-WaitReturnedFirstCoveringSampleAt $coverEnd`를 통한 단일 생성 경로를 사용한다.
- aggregator가 repository root를 기준으로 Compose 실제 SHA-256을 계산한다.
- aggregator가 JSONL의 `failure=null/empty`이며 `timestamp >= coreInvocationCompletedAt`인 첫 valid sample을 직접 찾고 coverage·lifecycle·timeline과 exact 비교한다.
- stop/capture timestamp identity, canonical path containment, 고정 파일명, 실제 byte 수, cleanup 결과를 aggregator에서 검증한다.

## 검증 결과

- PowerShell/Node 정적 검사: 통과
- fixture A~S 및 targeted fixture T1~T14: 통과
- 개별 PLAN·six-core PLAN manifest: `{path, sha256}` 7개 descriptor 확인
- PLAN ledger: started/warm-up/core/k6 모두 0
- BASELINE/REMEDIATION production probe: 이전 gate에서 full Compose·health·collector·cleanup 통과

## 판정

`EXP123_READY_FOR_SIX_CORE_RUNS`

성능 실행과 정책 판정은 아직 수행하지 않았다.
