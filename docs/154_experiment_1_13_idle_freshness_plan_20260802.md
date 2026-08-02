# Experiment 1-13 계획 — Idle Connection Freshness Remediation

## 질문

Node mock의 5,000ms keep-alive timeout보다 짧은 client `maxIdleTime=4,000ms`를 적용하면 stale pooled connection 재획득 패턴과 AI PrematureClose가 제거되거나 유의하게 감소하는가?

## 목적

Experiment 1-12가 connection-level에서 지지한 `mock close → pooled connection 재획득 → request prepared → PrematureClose` 패턴에 최소 remediation 하나만 적용하고, reliability 개선과 성능 guardrail을 paired comparison으로 검증한다.

## 가설

- H1: baseline 3회 중 2회 이상에서 stale reuse mechanism이 재현된다.
- H2: remediation 3회 모두에서 `mock-close-before-acquire reused PREMATURE_CLOSE=0`이다.
- H3: remediation의 AI PrematureClose 합계가 baseline보다 90% 이상 감소한다.
- H4: 새로운 uncontrolled failure가 생기지 않고 전체 uncontrolled failure가 baseline median보다 증가하지 않는다.
- H5: HTTP 200 median과 accepted p95 median은 baseline 대비 10% 이내 guardrail을 유지한다.

## 고정 조건

- VU/initial VU 200
- frame/reconnect 1초
- AI 2초, storage 100ms
- duration 105초, client timeout 10초, drain 30초
- app 2 CPU/3 GiB
- shared outbound pool max 400, pending 800
- DB pool 10
- full-path admission ENFORCE 320
- 같은 Base64 fixture, auth, DB, storage, completion contract
- 같은 source commit, application/mock image, runner, JVM/Node, Compose 본문
- 각 run마다 app/mock/DB/fixture fresh recreate/reset

## 단일 변경 변수

```text
BASELINE:    DOENG_EXTERNAL_MAX_IDLE_TIME_MS=0
REMEDIATION: DOENG_EXTERNAL_MAX_IDLE_TIME_MS=4000
```

다른 pool, timeout, retry, admission, scheduler, resource, workload, mock 설정은 변경하지 않는다.

## 실행 순서와 반복

```text
PAIR-01: BASELINE-001 → REMEDIATION-001
PAIR-02: BASELINE-002 → REMEDIATION-002
PAIR-03: BASELINE-003 → REMEDIATION-003
```

각 run은 fresh-JVM warm-up 뒤 core를 실행한다. 총 6개 core만 허용하며 추가 실행하지 않는다.

## 사전 deterministic gate

1. 기본값 0은 maxIdleTime을 provider builder에 지정하지 않는다.
2. 음수는 명확한 configuration validation failure다.
3. test server가 connection을 유지하는 동안 client maxIdle 500ms, idle 800ms 뒤 두 번째 요청은 새 channel을 사용한다.
4. maxIdle 미설정 상태의 같은 순서는 기존 channel을 재사용한다.
5. maxIdle 500ms라도 2초 active response는 중단되지 않는다.
6. 기존 diagnostic/admission/correlation/lifecycle/positive-control 및 Java 11 clean test를 유지한다.

## 측정 지표

Primary mechanism:

- AI PrematureClose request/event
- NEW/REUSED PREMATURE_CLOSE
- mock-close-before/after-acquire
- REQUEST_PREPARED without REQUEST_SENT

Reliability/outcome:

- HTTP 500, client timeout, TypeError/connection error, controlled 503
- 전체 uncontrolled failure
- HTTP 200, mission completion, AI/storage/DB completion

Guardrail:

- accepted p50/p95/p99
- app CPU/memory, event-loop delay
- new/reused connection, connection churn
- pending acquire, max in-flight, drain time-to-zero

## Validity

각 run에서 pre-run idle, health, 200명 login, strict/distinct auth, fixture hash, accounting, unfinished 0, DB/storage consistency, collector, load-stop/drain, source/image/Compose provenance를 확인한다. 나쁜 성능은 INVALID 이유가 아니다.

하나라도 instrumentation/configuration validity를 충족하지 못하면 자동 재실행 없이 전체 판정을 `INCONCLUSIVE_INVALID_RUN`으로 제한한다.

## 판정

### ACCEPTED_REMEDIATION

- 6개 core 모두 VALID
- baseline 3회 중 2회 이상 stale reuse 재현
- remediation 3회 모두 mock-close-before-acquire reused PREMATURE_CLOSE 0
- AI PrematureClose 합계 90% 이상 감소
- 새 uncontrolled failure category 없음
- 전체 uncontrolled failure median 증가 없음
- HTTP 200 median 10% 초과 감소 없음
- accepted p95 median 10% 초과 악화 없음

### EFFECTIVE_BUT_NOT_ACCEPTED

mechanism 제거/90% 감소는 충족하지만 failure 또는 성능 guardrail을 위반한다.

### NOT_EFFECTIVE

stale reused PREMATURE_CLOSE가 지속되거나 AI PrematureClose 감소가 90% 미만이거나 같은 failure가 다른 이름으로 이동한다.

### INCONCLUSIVE_NOT_REPRODUCED

baseline 3회 중 2회 이상에서 stale reuse가 재현되지 않는다.

### INCONCLUSIVE_INVALID_RUN

6개 core 중 하나라도 validity gate에 실패한다.

## 결과 위치

- raw: `experiment/results/RUN-20260802-EXP113-*/`
- paired/condition/config/keepalive/verdict summary: Experiment 1-13 결과 artifact
- 문서: `docs/155_experiment_1_13_idle_freshness_result_20260802.md`

## 검증 방법

- Java 11 clean test
- Node/mock syntax
- PowerShell runner parse
- rendered Compose diff
- source/image/fixture provenance
- request/connection/packet aggregation
- 3회 개별값, 합계, min/max, median 및 비율 비교

## Hard stop

6개 core와 집계 뒤 종료한다. 4초 이외 값, maxLifeTime, background eviction, LIFO, retry, pool/admission/mock timeout/resource/VU/MVC 변경 또는 추가 core는 수행하지 않는다.

