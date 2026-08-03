# Experiment 1-17 — Fresh-First Lifecycle A/B Preregistration

작성일: 2026-08-03
상태: 사전등록 완료. 실행 전 계약이며 아직 run은 없음.

## 질문과 가설

질문: `FRESH_FIRST_LIFECYCLE_POLICY_V1`이 Experiment 1-13의 stale reused AI PrematureClose mechanism을 줄이면서 reliability·latency·운영 guardrail을 유지하는가?

- H1: baseline 3회 중 최소 2회에서 stale reused mechanism이 재현된다.
- H2: remediation 3회 모두 `mock-close-before-acquire reused PrematureClose=0`이다.
- H3: remediation AI PrematureClose 합계는 baseline 대비 90% 이상 감소한다.
- H4: 새 uncontrolled failure·duplicate mock handler·transport 계열 HTTP 500이 생기지 않는다.
- H5: HTTP 200 median과 accepted p95 median은 각각 baseline median 대비 10% 초과 악화되지 않는다.

## Baseline과 remediation

| 조건 | Leasing | maxIdle | background eviction | retry / pool / mock |
|---|---|---:|---:|---|
| BASELINE | existing default FIFO | 0; 미호출 | disabled; 미호출 | current default 유지 |
| REMEDIATION | LIFO | 3,000ms | 1,000ms | current default 유지 |

모든 remediation 값은 `FRESH_FIRST_LIFECYCLE_POLICY_V1` 하나의 복합 변경이다. 개별 설정을 별도 arm으로 분해하거나 값을 sweep하지 않는다.

## Controlled diff

향후 구현 후 rendered Compose/config diff가 허용할 값은 다음 세 개뿐이다.

```text
DOENG_EXTERNAL_LEASING_STRATEGY: FIFO → LIFO
DOENG_EXTERNAL_MAX_IDLE_TIME_MS: 0 → 3000
DOENG_EXTERNAL_EVICTION_INTERVAL_MS: 0 → 1000
```

source, image, provider max/pending, timeout, pool mode, admission, mock/server keep-alive, workload, fixture, auth, DB/storage contract는 두 arm에서 동일해야 한다. shared mode에서는 token/AI/storage가 같은 external provider를 사용하므로 이 정책은 해당 shared provider에 일관되게 적용된다.

## Deterministic implementation gates

부하 실행 전에 모두 통과해야 한다. 이번 문서 작성 시점에는 구현하거나 실행하지 않았다.

| Gate | 검증 | 통과 기준 |
|---|---|---|
| A — baseline preservation | policy off source/runtime config | FIFO default, maxIdle 미설정, background eviction disabled; 기존 builder semantics 보존 |
| B — LIFO leasing | 최소 두 idle channel의 release 순서 통제 후 acquire | 가장 최근 release channel 사용. 직접 runtime 검증이 어려우면 1.0.28 API/source와 runtime config 출력으로 대체하고 한계 기록 |
| C — background idle eviction | release 후 후속 acquire 없이 대기 | 3초 eligibility + 1초 scan 범위 뒤 closeFuture 관측, 다음 요청은 새 channel |
| D — active response protection | active 2초 response | maxIdle=3초 때문에 active response가 중단되지 않음 |
| E — retry invariance | production source diff | `.disableRetry`, `retry`, `retryWhen` 미추가 |

하나라도 실패하면 A/B 부하를 시작하지 않고 `INVALID`로 중단한다.

## A/B run 계약

총 6 core run, 추가 run 금지.

```text
PAIR-01: BASELINE-001 → REMEDIATION-001
PAIR-02: BASELINE-002 → REMEDIATION-002
PAIR-03: BASELINE-003 → REMEDIATION-003
```

각 core 전 fresh-JVM warm-up과 health/idle/config/provenance gate를 수행한다. 동일 post-implementation source commit·application/mock image·runner를 사용한다. 조건별 fresh app/mock/DB recreate/reset과 fixture/auth/DB/storage consistency 검증을 유지한다.

## 고정 workload와 환경

Experiment 1-13 기준을 그대로 사용한다.

- VU/initial VU 200, frame/reconnect 1초
- AI delay 2,000ms, storage delay 100ms
- duration 105초, client timeout 10초, drain 30초
- app 2 CPU / 3GiB
- shared outbound pool max 400, pending 800; DB pool 10
- full-path admission ENFORCE 320
- 동일 Base64 fixture, auth, DB/storage/completion contract, JVM/Node version, runner, container image construction
- application continuous snapshot OFF, mock continuous polling OFF, DB/container/pool collector 및 load-stop/drain/consistency artifact는 Experiment 1-13과 동일하게 유지

## Measurement validity

다음은 INVALID 사유다: pre-run contamination, 설정/rendered compose/provenance mismatch, required raw artifact·collector·drain·consistency 검증 실패, reset 실패, deterministic gate 실패. 높은 error/p95/backlog 자체는 system outcome이며 validity 실패가 아니다.

## Primary success gate — ADOPT

다음을 모두 만족해야 한다.

1. baseline/remediation 3회씩 모두 measurement-valid
2. baseline 3회 중 최소 2회에서 stale reused mechanism 재현
3. remediation 3회 모두 `mock-close-before-acquire reused PrematureClose=0`
4. remediation AI PrematureClose 합계가 baseline보다 90% 이상 감소
5. remediation 3회 모두 AI transport 계열 HTTP 500=0
6. logical request/requestId별 duplicate mock handler=0
7. 새 uncontrolled failure 없음

3 또는 5가 하나라도 실패하면 `ADOPT`하지 않는다.

## 성능·운영 guardrail

수집: HTTP 200 median, accepted p95 median, successful completion, connection creation, active/idle/pending connection, connect/pending acquire timeout, file descriptor/ephemeral port 오류, app CPU/memory.

- HTTP 200 median: baseline median 대비 10% 초과 감소 금지
- accepted p95 median: baseline median 대비 10% 초과 악화 금지
- connect failure, pending acquire timeout, FD/port exhaustion 징후, 전체 uncontrolled failure 증가는 운영 guardrail 실패
- connection creation 증가는 단독 실패가 아님

## 판정과 rollback

| 판정 | 기준 |
|---|---|
| `ADOPT` | primary gate와 모든 guardrail 통과 |
| `NOT_EFFECTIVE` | stale reuse/PrematureClose가 기준만큼 감소하지 않음 |
| `RELIABILITY_IMPROVED_BUT_TOO_COSTLY` | reliability 성공, 성능·운영 guardrail 실패 |
| `BASELINE_NOT_REPRODUCED` | baseline 3회 중 2회 미만 재현 |
| `INVALID` | validity, controlled diff, reset, artifact 또는 deterministic gate 실패 |

rollback은 policy 미채택 및 다음 baseline 상태 복귀다.

```text
FIFO default
maxIdleTime 0 / builder 미호출
background eviction disabled / builder 미호출
```

## Hard stop

정확히 6 core를 집계한 뒤 종료한다. 결과에 따라 cycle/VU/value/interval/retry/pool/mock timeout을 바꾸거나 MVC·추가 부하로 넘어가지 않는다.
