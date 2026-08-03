# Experiment 1-17 — Fresh-First Connection Lifecycle Policy Design

작성일: 2026-08-03
상태: 사전등록 설계. 구현·deterministic gate·부하 실행은 수행하지 않음.

## 선행 Evidence

- Experiment 1-13 baseline 3/3에서 stale reused AI premature-close mechanism이 관측됐다.
- 같은 실험에서 `maxIdleTime=4000ms` 단독 적용은 `NOT_EFFECTIVE`였다. AI PrematureClose 합계는 baseline 78건 대비 168건으로 감소하지 않았고, reused·mock-close-before-acquire pattern도 잔존했다.
- Experiment 1-14/1-15는 request/lease 결합의 한계를 분리했으며, 1-16은 close/acquire race에서 client closeFuture 완료 뒤 pool이 closed old channel을 다음 acquire 후보에서 제외하는 경로를 8/8 확인했다.
- 따라서 현재 Evidence는 peer close가 client event loop/pool 반영보다 먼저 일어나는 경계가 stale reuse와 연결될 수 있다는 bounded inference만 지지한다. 단독 원인이나 Reactor Netty 결함은 확정하지 않는다.

## Bounded mechanism

```text
peer 또는 kernel 수준 close 도착
→ client event loop의 close 반영 전 pool acquire/request preparation
→ reused channel에서 PrematureClose 가능성

client close 처리 완료
→ pool acquire
→ closed channel 제외
→ 새 channel 제공
```

따라서 이번 정책은 closed channel 판정을 새로 구현하거나 retry를 추가하지 않는다. peer timeout 근처의 오래 idle한 connection을 덜 선택하고, peer보다 앞서 idle connection을 정리하는 복합 lifecycle policy다.

## 선택 정책

정책명: `FRESH_FIRST_LIFECYCLE_POLICY_V1`

| 구성 | Baseline | Remediation |
|---|---|---|
| leasing strategy | Reactor Netty 1.0.28 current default FIFO; builder selector 미호출 | LIFO |
| maxIdleTime | 0; builder 미호출 | 3,000ms |
| background eviction | disabled; builder 미호출 | 1,000ms |
| maxLifeTime | 미설정 | 미설정 |
| custom eviction predicate | 미설정 | 미설정 |
| transport retry | Reactor Netty default 유지 | 동일 |
| application retry | 없음 | 추가하지 않음 |
| mock/server keep-alive | 5,000ms 유지 | 동일 |

향후 구현 property는 기존 naming과 맞춰 다음 의미로 제한한다.

```text
DOENG_EXTERNAL_LEASING_STRATEGY=FIFO|LIFO
DOENG_EXTERNAL_MAX_IDLE_TIME_MS=0|3000
DOENG_EXTERNAL_EVICTION_INTERVAL_MS=0|1000
```

`FIFO`, 0, 0일 때는 현재 baseline과 같게 lifecycle API를 호출하지 않는다. `LIFO`, 양수 maxIdle, 양수 eviction interval일 때에만 각각 `builder.lifo()`, `builder.maxIdleTime(...)`, `builder.evictInBackground(...)`를 호출한다.

## 각 설정의 역할

### LIFO

현재 explicit strategy가 없는 provider는 Reactor Netty 1.0.28 default FIFO를 사용한다. FIFO는 먼저 release된 idle connection을 먼저 선택할 수 있다. LIFO는 가장 최근에 정상 사용된 idle connection을 우선해, under-utilized pool에서 오래 idle한 channel의 선택 우선순위를 낮춘다. LIFO 자체는 idle channel 제거 기능이 아니다.

### maxIdleTime 3,000ms

Node 20 mock의 effective keep-alive timeout은 5,000ms다. 4,000ms 단독 정책은 lazy eviction/acquire boundary를 넘지 못했다. 이번에는 maxIdle eligibility를 3,000ms로 앞당긴다.

### background eviction 1,000ms

Reactor Netty 1.0.28의 `maxIdleTime`은 pool lifecycle 경계에서만 검사될 수 있으므로, `evictInBackground(Duration.ofSeconds(1))`로 idle 후보를 주기적으로 검사한다. 명목상 3,000ms eligibility와 최대 약 1,000ms scan 간격을 합쳐 약 4,000ms 이내에 정리하는 것을 목표로 하며, scheduler delay를 포함한 hard real-time 보장은 주장하지 않는다.

5,000ms peer timeout보다 약 1,000ms 앞선 설계 여유는 4,000ms 단독 정책이 실패한 Evidence와 background eviction 부재라는 source 사실을 함께 반영한 단일값이다. 3,000ms/1,000ms는 최적화 탐색 결과가 아니다.

## API·source 적합성

- 현재 `ExternalHttpClientConfig.buildProvider`는 `maxConnections`, pending limit/timeout, 양수 `maxIdleTime`만 builder에 적용한다.
- 현재 `ExternalServiceProperties`와 `application.yml`은 `DOENG_EXTERNAL_MAX_IDLE_TIME_MS`를 `max-idle-time-ms`에 결합하고 기본 0을 제공한다.
- 현재 source에는 `.lifo()`, `.fifo()`, `.evictInBackground(...)`, `.disableRetry(...)`, application `retry*` 호출이 없다.
- Reactor Netty 1.0.28 API line에는 `ConnectionProvider.ConnectionPoolSpec.lifo()`, `maxIdleTime(Duration)`, `evictInBackground(Duration)`가 있고 `HttpClient.disableRetry(boolean)`도 존재한다. 구현 단계에서는 이 dependency version을 바꾸지 않는다.

## Claim 제한

A/B가 성공해도 다음만 주장한다.

> LIFO, 3초 maxIdleTime, 1초 background eviction을 묶은 Fresh-First lifecycle policy가 이 고정 workload에서 stale reuse와 AI PrematureClose를 줄였다.

다음은 주장하지 않는다: 개별 설정의 단독 효과, 3초/1초의 최적성, FIFO의 직접 원인성, Reactor Netty bug, 다른 AI/S3 환경으로의 일반화.

## 예상 비용과 remaining risk

- 더 빠른 idle eviction과 LIFO는 connection creation/churn을 바꿀 수 있다.
- background scan은 작은 추가 pool 작업을 유발한다.
- connection 생성 증가 자체는 실패가 아니며, connect failure·pending acquire timeout·file descriptor/ephemeral port 징후·uncontrolled failure 증가가 운영 실패다.
- request/lease production-load attribution의 한계, host variability, mock 5초 keep-alive의 외부 일반화 한계는 유지된다.

## 구현 전 경계

이 문서는 정책값과 검증 계약만 확정한다. production source, Compose, image, runner, deterministic test, VU workload를 변경하거나 실행하지 않았다.
