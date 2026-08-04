# Experiment 1-23 Provenance·Timestamp·Path·Invocation Ledger Closure

## 범위

Exp122 closure와 Exp123의 조건·frozen image·Compose stack·collector 계약은 변경하지 않았다. 실제 Exp123 warm-up·k6·core 성능 실행도 하지 않았다.

## 반영 사항

- Compose provenance 비교를 객체의 `path` 문자열 기준으로 정정했다.
- `run-config.composeFiles[i].sha256`, `runtime-provenance.composeFiles[i].sha256`, 현재 repository 파일 SHA-256의 3자 일치를 검증한다.
- stop/capture timeline timestamp를 metadata와 exact string identity로 검증하고 완료 시각이 시작 시각보다 빠르지 않은지 확인한다.
- capture 경로를 canonical absolute path와 relative path로 검사해 sibling/outside path를 거부하며, 파일명을 고정한다.
- capture stdout/stderr/combined byte 수와 실제 파일 크기를 비교한다.
- first-covering sample을 runner가 명시적으로 `-WaitReturnedFirstCoveringSampleAt $coverEnd`로 coverage helper에 전달한다.
- coverage·lifecycle·timeline의 first-covering timestamp 4-way identity를 검증한다.
- six-core ledger가 실제 `experiment/results/SMOKE-*`, `experiment/results/RUN-*` 경로를 기준으로 warmup/core/k6 invocation을 계산하도록 정정했다. 현재 workload 구조에서는 core invocation이 k6 invocation으로 기록된다.
- targeted fixture T1~T14를 추가했다.

## 검증 결과

- PowerShell/Node 정적 검사: 통과
- A~S + T1~T14 fixture: 통과
- six-core PLAN: Compose `{path, sha256}`, workload, collector, frozen image, policy 기록; started/warm-up/core/k6 모두 0
- BASELINE/REMEDIATION production probe: full Compose·health·collector readiness/summary·cleanup 통과

## 판정

`EXP123_READY_FOR_SIX_CORE_RUNS`

이는 사전등록된 six-core 실행을 시작할 수 있는 provenance·timestamp·path·ledger 계약이 충족됐다는 뜻이다. 성능 결과와 정책 효과는 아직 없다.

## 금지 준수

실제 warm-up, k6, core, 성능 분석, 정책 결정, Exp122 raw/closure 수정은 수행하지 않았다.
