# Experiment 1-19 여섯 core run 실행 준비 상태

작성일: 2026-08-03
상태: 준비 완료, 실행 대기

## DECISION

`READY_FOR_SIX_CORE_RUNS`

## SOURCE COMMIT

`270349fa7937eb4486087d34184461ae6aaab10a`

## HARNESS COMMIT

`13ab71b` 이후 runtime controlled diff/schema 보완이 작업 트리에 존재한다. 이 보완은 core 실행 전에 별도 commit/push한다.

## IMAGE ID

- application: `sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168`
- local RepoDigest: `doeng-flux-exp119-fresh-first-20260803@sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168`
- mock: `sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1`

## BASELINE CONFIG

- FIFO / max idle 0ms / eviction 0ms

## REMEDIATION CONFIG

- LIFO / max idle 3,000ms / eviction 1,000ms

## CONTROLLED DIFF

정책 세 변수 외 rendered Compose 차이는 없으며, runtime container environment와 Java 11 property-binding test로 적용 경로를 확인했다. 근거는 `docs/171_experiment_1_19_fresh_first_ab_preflight_result_20260803.md`에 있다.

Rendered Compose와 runtime snapshot은 lifecycle 세 값 외 차이가 없다. pool mode SHARED, pool 400/pending 800, pending acquire timeout 10,000ms, connect 2,000ms, response 10,000ms, admission 320은 두 arm에서 동일하다.

## PREFLIGHT RESULT

두 arm의 fresh recreate·health·mock/DB reset·fixture/auth·collector gate가 통과했고 core workload는 0회다.

## COLLECTOR READINESS

pool endpoint 단발 snapshot, DB collector, container collector, Node runtime을 확인했다. future core에서는 application continuous snapshot OFF, mock continuous polling OFF, JFR OFF를 유지한다.

## AGGREGATOR READINESS

schema는 validity, primary reliability(AI premature close·reused channel·HTTP 500 등), guardrail, 사전등록 decision enum을 준비했으며 `NOT_RUN` 상태다.

## 이후 core 계약

- arm별 VALID core run 3개, 총 6개
- VU 200, duration 105초, frame/reconnect 1초
- AI 2,000ms, storage 100ms, request timeout 10초, drain 30초
- app 2 CPU/3GiB, pool 400/pending 800, DB pool 10, admission 320
- 동일 fixture/auth/token/DB/storage/completion contract
- fresh JVM, pre-run idle gate, load-stop snapshot, drain, consistency verification
- application continuous snapshot OFF, mock continuous polling OFF, JFR OFF; DB/container monitor ON

## future aggregation schema

`aggregator-schema.json`은 다음 core artifact와 비교 항목을 요구하도록 준비됐다.

- client result/progress, pool time-series, application raw log, DB/container, mock load-stop/drain, verification, provenance
- successful RPS, accepted p95/p99, controlled 503, timeout, unfinished backlog, transport failure, pool active/pending, connection lifecycle evidence, CPU/memory, DB state

현재 schema의 `executionStatus`와 `decisionState`는 모두 `NOT_RUN`이다. 빈 결과를 채우거나 가짜 aggregate를 만들지 않았다.

## 시작 금지 조건

core를 시작하기 전에 다음 중 하나라도 달라지면 해당 run을 시작하지 않고 harness 상태를 다시 확인한다.

- application/mock image ID 또는 frozen source provenance 불일치
- lifecycle 세 변수 이외의 rendered Compose 차이
- pre-run mock in-flight non-zero
- DB/mock reset 또는 fixture/auth 200-token contract 실패
- health, collector, load-stop/drain artifact 경로 실패

## 현재 결정

`READY_FOR_SIX_CORE_RUNS`.

이 상태는 A/B 실행의 시작 허가 전제이며, policy 채택·rollback·성능 우위의 판정은 아니다.

## NEXT ALLOWED STEP

승인 후 `PAIR-01: BASELINE-001 → REMEDIATION-001`만 시작할 수 있다. 이후 PAIR-02, PAIR-03도 같은 frozen contract를 사용한다.

## HARD STOP

이 문서 작성만으로 여섯 core, 105초 VU workload, policy 채택/rollback, 추가 가설, MVC 비교를 자동 실행하지 않는다.
