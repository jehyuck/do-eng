# Experiment 1-23 Aggregator Validity·PLAN Single-Path Closure

## 범위

Exp122 closure와 Exp123 조건·frozen image·Compose·collector 계약은 변경하지 않았다. 실제 warm-up·k6·core 성능 실행은 하지 않았다.

## 반영 사항

- six-core PLAN runner가 manifest를 다시 쓰지 않고, 각 core runner의 canonical manifest를 검증만 한다.
- PLAN manifest에 expected runId, runDate, condition, PLAN mode, Compose descriptor 7개와 lowercase SHA-256 형식을 검증한다.
- aggregator가 arm별 expected runId/condition/date/mode를 directory identity와 함께 검증한다.
- BASELINE FIFO/0/0, REMEDIATION LIFO/3000/1000 policy를 run-config와 runtime provenance에 대해 exact 비교한다.
- collector summary status/stop-signal/failures/sample count와 lifecycle identity를 검증한다.
- coverage 전체 flag·counter·timeline identity와 JSONL first-covering sample을 직접 검증한다.
- Compose exact set, duplicate/missing/extra path, run-config/runtime/repository SHA-256 3-way identity를 검증한다.
- required artifact size gate, terminal exclusivity, stop/capture full contract를 aggregator에 반영했다.
- targeted fixture W1~W17을 추가했다.

## 검증 결과

- PowerShell/Node 정적 검사: 통과
- A~S·T1~T14·W1~W17 fixture: 통과
- six-core PLAN: manifest 재작성 없음, 7개 canonical descriptor 검증, started/warm-up/core/k6 모두 0

## 판정

`EXP123_READY_FOR_SIX_CORE_RUNS`

실제 성능 실행과 정책 판정은 아직 수행하지 않았다.
