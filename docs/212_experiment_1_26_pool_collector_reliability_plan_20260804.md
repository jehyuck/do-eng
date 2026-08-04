# Experiment 1-26 — Pool Collector Reliability Recovery

## 질문

Exp125의 단일 management polling timeout이 collector의 관측 공백 또는 잘못된 종료를 만들지 않도록, 실패를 보존하고 다음 poll을 계속 수행하는가?

## 고정 조건

- frozen application/mock image, Compose 7개, workload/resource, BASELINE/REMEDIATION 정책은 Exp125와 동일
- interval 1,000 ms, request timeout 5 s, max duration 300 s
- 최대 동시 polling 요청 1개; 이전 요청이 끝나기 전 새 요청을 겹치지 않음
- warm-up, k6, core, 성능 분석, 정책 판정은 수행하지 않음

## Collector 계약

각 시도는 `attemptNumber`, 시작/종료 시각, elapsed milliseconds, PID, HTTP status, parse 결과, exception type/message, consecutiveFailures를 JSONL에 남긴다. 실패 row도 삭제하지 않는다. stop signal은 pending request 이후 bounded하게 처리하고 summary에 보존한다.

## Reliability fixture

Z1 정상, Z2 단일 timeout, Z3 연속 timeout, Z4 malformed JSON, Z5 HTTP 500, Z6 pending 중 stop signal, Z7 core boundary coverage, Z8 maximum-gap rejection을 synthetic fixture로 검증한다.

## 실행 순서

1. Exp125 closure 및 raw hash inventory 확인
2. collector idle reliability 300초 검증
3. Z1~Z8 fixture 검증
4. BASELINE production-path probe
5. REMEDIATION production-path probe
6. synthetic six-run aggregator fixture
7. Exp126 six-core PLAN 검증

모든 단계는 부하를 생성하지 않으며, readiness가 충족되기 전 Exp126 core 실행은 금지한다.

## 판정

모든 gate 통과 시 `EXP126_READY_FOR_SIX_CORE_RUNS`; 하나라도 실패하면 `EXP126_NOT_READY`로 기록한다.
