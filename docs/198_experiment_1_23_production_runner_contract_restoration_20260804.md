# Experiment 1-23 Production Runner Contract 복원

## 작업 범위

Exp122의 전체 Compose·이미지·정책·collector·artifact 계약을 Exp123 production runner에 연결했다. 실제 VU warm-up, k6/load, core 성능 실행은 수행하지 않았다.

## 복원한 계약

- Exp122 전체 Compose override 7개를 warm-up/core에 동일하게 전달
- frozen application/mock image ID를 EXECUTE 전에 검증
- BASELINE FIFO/0/0, REMEDIATION LIFO/3000/1000 정책을 프로세스 환경에 바인딩하고 종료 시 복원
- warm-up storage delay 100ms 고정
- collector readiness와 core 종료 이후 실제 sample timestamp 확인
- atomic stop signal, summary의 stopped-by-signal·observed·failures·exit 상태 확인
- 실제 collector coverage/lifecycle artifact 생성
- application container stop 및 post-stop log capture wrapper 연결
- runtime provenance와 execution timeline 기록
- structural/committed artifact gate 및 terminal marker 경로 연결
- PLAN에서는 warm-up/k6/core 카운트를 0으로 고정

## 검증 결과

- PowerShell 스크립트 구문 파싱: 통과
- collector lifecycle fixture A-N: 통과
- BASELINE/REMEDIATION collector probe: 각각 `CORE_BOUND_COLLECTOR_PROBE_READY`
- six-core PLAN: `EXP123_PLAN_READY`
- PLAN ledger: requested 6, started/completed/failed/warm-up/k6/core 모두 0
- 실제 performance run: 수행하지 않음

## 판정

`EXP123_READY_FOR_SIX_CORE_RUNS`

이는 runner가 사전등록된 6-core 실행을 시작할 준비가 되었다는 뜻이며, 성능 결과나 정책 효과를 의미하지 않는다.

## 남은 제한

실제 six-core 실행 전에는 container stop, post-stop capture, committed artifact gate의 런타임 결과가 존재하지 않는다. 따라서 본 문서는 harness 복원 Evidence이며 성능·정책 Claim을 포함하지 않는다.
