# Experiment 1-14 Research — WebClient Connection Lifecycle Audit

작성일: 2026-08-03
범위: 코드·의존성·Experiment 1-12/1-13 원시 artifact 검토만 수행. 새 부하 실행, 설정 변경, production code 변경은 수행하지 않았다.

## 1. 현재 lifecycle 구성

기준 branch/commit은 `experiment/doeng-idle-freshness-remediation`의 source `900b5f95864cc19e257eeca27a6807df83c0291d`, result `9d870c24516a8579e580dae726f3ababcb022996`이다.

| 항목 | 실제 구성 | 근거 |
| --- | --- | --- |
| Java / Spring Boot | Java 11, Spring Boot 2.7.9 | `backend/doEngGameFlux/build.gradle` |
| Reactor Netty / Reactor Core | 1.0.28 / 3.4.27 | Gradle resolved cache의 `reactor-netty-*.1.0.28.jar`, `reactor-core-3.4.27.jar` |
| provider | `doeng-external` 공유 `ConnectionProvider` | `ExternalHttpClientConfig.java:57-67, 115-131, 147-174` |
| pool mode | `SHARED` | `docker-compose.experiment-1-12-connection-attribution.yaml:14-17` |
| max connection / pending | 400 / 800 | 같은 Compose 15-17행 |
| acquire / response timeout | 각 10,000ms | `ExternalHttpClientConfig.java:153-159, 197-203` |
| maxIdleTime 기본 | 0: builder 호출하지 않음 | `ExternalServiceProperties.java:20-24`, `ExternalHttpClientConfig.java:158-160` |
| Experiment 1-13 단일 변경 | `DOENG_EXTERNAL_MAX_IDLE_TIME_MS=0` 대 `4000` | `docker-compose.experiment-1-13-idle-freshness.yaml:5-6`, run-config |
| maxLifeTime | 설정 없음 | `buildProvider`에 호출 없음 |
| evictInBackground | 설정 없음 | `buildProvider`에 호출 없음 |
| custom eviction predicate | 설정 없음 | `buildProvider`에 호출 없음 |
| explicit leasing strategy | 설정 없음 | `.fifo()` / `.lifo()` 호출 없음 |
| application retry | 설정 없음 | `AiGameController.java`에 `retry*` operator 없음 |
| transport retry disable | 설정 없음 | `ExternalHttpClientConfig.java:197-212`에 `.disableRetry(...)` 없음 |

AI와 storage, token WebClient 모두 pool mode가 `SHARED`이면 같은 provider를 선택한다. 따라서 이번 결과의 AI connection lifecycle은 AI 전용 pool의 결과가 아니라 `doeng-external` 공유 pool의 remote-host pool 결과다.

## 2. Reactor Netty 1.0.28 API와 실제 적용의 구분

### Leasing strategy

Reactor Netty 1.0.28의 API default leasing strategy는 JVM system property `reactor.netty.pool.leasingStrategy`가 없을 때 FIFO다. FIFO는 현재 idle channel 중 먼저 release된 연결(LRU)을 다음 acquire에 준다. LIFO는 가장 늦게 release된 연결(MRU)을 준다. [ConnectionProvider source](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-core/src/main/java/reactor/netty/resources/ConnectionProvider.java#L75-L92), [lifo/fifo API](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-core/src/main/java/reactor/netty/resources/ConnectionProvider.java#L648-L672).

현재 source는 전략을 명시하지 않고, 실험 Compose 및 repository에서 system property 설정도 확인되지 않았다. 그러므로 **현재 구성의 runtime default는 FIFO로 판단 가능**하다. 다만 FIFO 자체만으로 `PrematureCloseException`의 직접 원인이라고 단정할 수는 없다. FIFO는 under-utilized pool에서 더 오래 idle이었던 연결을 먼저 선택하므로, peer keep-alive 만료와의 노출 가능성을 높이는 선택 규칙일 뿐이다.

### maxIdleTime과 eviction 시점

`maxIdleTime`은 idle 상태가 된 channel을 닫기 위한 기간이며, 기본값은 미지정이다. `maxLifeTime`도 기본 미지정이다. [1.0.28 API](https://projectreactor.io/docs/netty/1.0.28/api/reactor/netty/resources/ConnectionProvider.ConnectionPoolSpec.html). 이 프로젝트의 0은 builder에 `maxIdleTime`을 전달하지 않는 뜻이다.

API는 “4,000ms가 되는 즉시 독립 timer가 반드시 닫는다”는 보장을 하지 않는다. 1.0.28에서 background eviction 기본값은 disabled이고, `evictInBackground(Duration.ZERO)`도 disabled다. background eviction을 켜면 pool이 주기적으로 제거 대상 connection을 검사한다. [API source](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-core/src/main/java/reactor/netty/resources/ConnectionProvider.java#L675-L688). 따라서 `maxIdleTime=4000`만 설정한 Experiment 1-13은 acquire/release 및 pool eviction 경계의 scheduling race를 제거했다고 말할 수 없다.

### custom predicate와 maxLifeTime

custom predicate는 설정되지 않았고, maxIdle/maxLife도 설정되지 않은 기본 상태에서는 persistent/active 여부가 기본 eviction에 관여한다. custom predicate를 넣으면 그 predicate가 기본 조건을 대체할 수 있다. [API source](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-core/src/main/java/reactor/netty/resources/ConnectionProvider.java#L590-L604). 이번 audit에서 custom predicate와 maxLifeTime을 후보 정책으로 채택하지 않는 이유다.

## 3. 기존 artifact가 확인한 연결 사실

Node 20 mock은 keep-alive 관련 option을 override하지 않았고, 응답은 `Connection: keep-alive`, `Keep-Alive: timeout=5`을 사용했다. 따라서 peer 기준 idle timeout은 5,000ms다. 근거는 `docs/155_experiment_1_13_idle_freshness_result_20260802.md`와 각 run의 `mock-requests.json`이다.

Experiment 1-13의 6개 core run은 모두 `measurementValidity=VALID`이다. baseline(0ms) AI `PrematureClose`는 78건, 4,000ms condition은 168건이었다. 4,000ms condition의 168건은 모두 `REUSED_CHANNEL`이고, 그 중 166건은 mock FIN/RST가 acquire보다 먼저 관측되었으며 `REQUEST_PREPARED`는 있으나 `REQUEST_SENT`는 없었다. 원시 근거는 각 run의 `connection-mechanism-details.jsonl`, `connection-mechanism-summary.json`, 그리고 condition summary다.

따라서 다음은 확인되었다.

1. stale pooled channel reuse 현상은 baseline과 4,000ms condition 모두에서 발생했다.
2. 단일 `maxIdleTime=4000`은 이 현상을 제거하지 못했다. Experiment 1-13의 판정은 `NOT_EFFECTIVE`다.
3. 해당 실패 표본은 request body가 전송된 뒤의 응답 실패가 아니라, 관측상 `REQUEST_SENT` 이전의 channel close였다.
4. 이 사실은 FIFO, background eviction 부재, client/server idle clock boundary 중 무엇이 primary cause인지 분리하지는 못한다.

## 4. server–client idle clock boundary 검토

요구한 이벤트의 보유 여부는 다음과 같다.

| 이벤트 | 보유 | request 단위 결합 가능성 |
| --- | --- | --- |
| mock response finished | 보유 (`MOCK_AI_RESPONSE_FINISHED`) | requestId와 socket tuple 보유 |
| client response received / completed / released | 보유 (`application-connections.jsonl`) | channel/lease/socket tuple 보유, 실패 lease에는 request binding 없음 |
| mock FIN/RST | 보유 (pcap 및 connection mechanism) | connection/lease 수준 |
| channel inactive | 보유 | connection/lease 수준 |
| next acquired / prepared / sent | 보유 | connection/lease 수준 |

성공 요청에 한해 socket tuple을 사용한 사후 비교는 가능했지만, client response/release event가 `MOCK_AI_RESPONSE_FINISHED`의 requestId와 완전하게 결합되어 있지 않다. 특히 문제의 pre-send failure는 `AI_REQUEST_CHANNEL_BOUND`가 기록되기 전에 실패하여 requestId–lease 결합이 빠진다. `connection-correlation-summary.json`도 premature 56건을 `MISSING_REQUEST_BINDING`으로 표시한다.

따라서 mock response-finished에서 client pool release까지의 시간, 그리고 그 값을 이용한 안전한 `maxIdleTime`을 현재 artifact만으로 **측정값으로 확정할 수 없다**. socket tuple 근사치는 병렬 연결 및 event boundary 누락 때문에 정책 값의 근거로 쓰지 않는다. 필요한 최소 추가 event는 AI requestId를 `REQUEST_PREPARED` 이전의 lease/channel에 결합해 남기고, 동일 requestId로 `RESPONSE_RECEIVED`·`RESPONSE_COMPLETED`·`RELEASED`를 기록하는 것이다.

## 5. Retry semantics와 POST 안전성

현재 application source에는 `retry`, `retryWhen`, `Retry`가 없고 `requestDecision`은 JSON `bodyValue(request)`를 가진 `POST /face`다 (`AiGameController.java:142-177`). 서버는 AI 결과가 true일 때에만 이후 storage와 DB 작업을 시작한다 (`180-199`).

그러나 Reactor Netty 1.0.28 `HttpClient`는 `disableRetry(false)`가 기본이며, connection-reset 발생 시 outgoing request의 retry-once 지원을 기본 활성화한다. [HttpClient API](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-http/src/main/java/reactor/netty/http/client/HttpClient.java#L606-L621). 내부 구현은 headers/body가 이미 전송되었다면 재시도를 끄고, 전송 전 connection reset이면 해당 channel을 non-persistent로 표시한 뒤 한 번 재시도한다. [HttpClientConnect source](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-http/src/main/java/reactor/netty/http/client/HttpClientConnect.java#L320-L365), [retry predicate](https://github.com/reactor/reactor-netty/blob/v1.0.28/reactor-netty-http/src/main/java/reactor/netty/http/client/HttpClientConnect.java#L635-L649).

즉 현재는 broad application retry가 아니라 transport-level pre-send retry가 이미 존재한다. `REQUEST_SENT`가 없는 1-13 표본은 이 경계와 부합하지만, 누락된 requestId–lease 결합 때문에 각 실패가 실제로 retry attempt까지 갔는지 request별로 확정하지는 못한다. POST body가 실제로 mock handler에 도달한 뒤에는 duplicate AI 처리 가능성이 있으므로, application retry 또는 post-send retry는 idempotency/correlation 보강 전에는 후보로 채택하지 않는다.

## 6. 후보 정책 비교

| 후보 | 평가 | 채택하지 않는 이유 또는 조건 |
| --- | --- | --- |
| A. LIFO + 측정 기반 maxIdle + background eviction | 가장 관련성 높은 lifecycle 후보 | LIFO는 freshest idle channel을 우선하지만, 안전한 maxIdle과 eviction interval을 산출할 request-bound clock evidence가 아직 없다. 지금 설정값을 고르면 임의값이 된다. |
| B. server keep-alive와 client maxIdle 정렬 | 보류 | server timeout 변경과 client 정책 변경을 함께 수행하면 원인을 분리할 수 없다. |
| C. pre-send PrematureClose 1회 application retry | 거절 | transport-level pre-send retry가 이미 기본 활성화되어 있고, POST duplicate 경계가 완전하게 결합되어 있지 않다. |
| D. maxLifeTime | 거절 | peer idle expiry가 아니라 connection age를 자르는 정책이며 현재 증거가 이를 primary mechanism으로 지지하지 않는다. |
| E. pool 비활성화/newConnection | 거절 | 재사용 자체를 제거해 churn/connection cost라는 다른 변수를 크게 만든다. |
| F. Reactor Netty upgrade | 거절 | lifecycle policy 검증과 version 변경을 같은 실험으로 묶을 수 없다. |

## 7. 확정된 사실, 제한된 추론, 미확인 사항

### 확인된 사실

- 현재 shared pool은 explicit 전략이 없고 Reactor Netty 1.0.28 default FIFO를 사용한다.
- maxIdle/maxLife/background eviction/custom predicate는 현재 baseline에서 모두 미설정이다.
- 4,000ms maxIdle 단독 정책은 6개 VALID core에서 stale reuse를 제거하지 못했다.
- Reactor Netty 내부 pre-send retry-once가 현재 WebClient에 적용될 수 있으며 application retry는 없다.

### 제한된 추론

- FIFO와 background eviction 부재는 오래 idle인 채널을 선택·보유할 기회를 남기므로 candidate A는 기술적으로 타당한 다음 후보이다.
- 그러나 이는 정책의 방향성일 뿐, 4,000ms보다 어떤 값이 안전한지 또는 어느 background interval이 필요한지를 증명하지 않는다.

### 미확인 사항

- 동일 request에서 mock response finish → client response/body complete → pool release의 정확한 차이
- pre-send failure별 Reactor Netty internal retry 실제 수행 여부와 retry attempt의 connection
- 실제 AI/S3 peer의 keep-alive 및 close 정책
- LIFO + eviction policy가 stale reuse를 실제로 줄이는지

## 8. 최종 lifecycle 정책 판정

**최종 정책: `INSUFFICIENT_EVIDENCE`**

후보 A를 지금 구현하거나 VU 부하로 시험하지 않는다. 다음 허용 작업은 lifecycle policy 변경이 아니라, requestId–lease 결합을 완성하는 단일 deterministic one-connection diagnostic이다. 그 diagnostic은 mock response-finished, client response-received/completed/released, next acquire/prepared/sent, mock close를 한 requestId와 동일 channel/lease에 기록해야 한다. 그 뒤에만 `LIFO + derived maxIdleTime + evictInBackground`을 하나의 정책으로 사전등록할 수 있다.

### 성공 / 실패 / rollback 기준 (향후 remediation 실험에만 적용)

- 성공: 사전등록한 lifecycle policy가 모든 VALID 반복에서 stale reused pre-send close를 제거하거나, 사전등록한 감소 기준을 충족하며 guardrail을 위반하지 않는다.
- 실패: stale reused pre-send close가 계속 발생하거나, connection churn·accepted latency·uncontrolled failure guardrail을 위반한다.
- rollback: policy overlay만 제거하고 현재 baseline인 FIFO, maxIdle 미설정, background eviction 미설정으로 복귀한다. application retry, pool size, admission, timeout, server keep-alive는 rollback에 포함하지 않는다.

## 9. 금지된 주장

- FIFO가 이번 모든 `PrematureCloseException`의 직접 원인이라는 주장
- 4,000ms가 Reactor Netty에서 정확히 4초 뒤 즉시 channel을 닫는다는 주장
- LIFO 또는 background eviction이 해결책임이 이미 증명되었다는 주장
- 현재 pre-send retry가 모든 POST 중복을 원천 방지한다는 주장
- local Node mock의 결과를 실제 AI/S3의 일반적 동작으로 확대하는 주장
