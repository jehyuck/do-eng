# Experiment 1-15 — Deterministic Connection Lifecycle Correlation Plan

작성일: 2026-08-03

## 질문

부하 없는 single-flight connection cycle에서 logical request, attempt, lease, channel, socket tuple, response completion, pool release, peer close, client channel inactive, 다음 acquire 및 transport retry 여부를 하나의 event stream으로 연결할 수 있는가?

## 선행 Evidence

- Experiment 1-13은 `maxIdleTime=4000ms` 단독 정책이 stale reused close를 제거하지 못한 `NOT_EFFECTIVE` 결과다.
- Experiment 1-14는 request-bound mock response finish → client release 시간이 부족하므로 lifecycle policy를 확정하지 않고 `INSUFFICIENT_EVIDENCE`로 판정했다.
- Reactor Netty 1.0.28의 transport retry-once는 pre-send connection reset에만 적용될 수 있으며, application retry는 없다.

## Instrumentation 설계

production source를 변경하지 않는다. 테스트 전용 Reactor Netty HTTP server/client와 structured JSONL event recorder를 만든다.

- `requestId`: 하나의 logical request
- `attemptId`: request의 전송 attempt. 이 테스트에서는 direct public hook이 없으므로 single-flight 순서로 `A1`을 부여한다.
- `leaseId`: channelId와 `ConnectionObserver.State.ACQUIRED` sequence의 조합
- `channelId`, local/remote socket tuple: Reactor Netty channel에서 직접 읽는다.

Reactor Netty 1.0.28의 public hook으로 직접 얻는 event만 기록한다. acquire/release는 `ConnectionObserver`의 `ACQUIRED`/`RELEASED`, response body completion은 `doAfterResponseSuccess`, peer close/client inactive는 server-side close와 client channel handler로 분리한다.

request가 acquire 전에 API 경계에서 직접 결합되는 public hook은 없다. 따라서 다음 표기를 고정한다.

```text
DIRECT_REQUEST_BINDING_NOT_AVAILABLE
DETERMINISTIC_SINGLE_FLIGHT_ATTRIBUTION_USED
```

이는 8 cycle 전체에서 한번에 하나의 request만 실행하고 pool max connection을 1로 제한하는 test isolation에만 적용한다. timestamp 근접성만으로 결합하지 않는다.

## Deterministic cycle

반복 수는 결과를 보지 않고 8회로 고정한다. 각 cycle은 다음 순서다.

1. `cycle-N-a`: test server에 POST 성공 → response body complete → pool release
2. `cycle-N-b`: 같은 WebClient에서 POST 성공. 이전 channel reuse를 Gate A로 확인한다. server는 이 응답 완료 뒤 test-only FIN을 보낸다.
3. client channel inactive를 확인한다.
4. `cycle-N-c`: 같은 WebClient에서 POST 성공. Gate B로 새 channel acquire를 확인한다.

test-only server의 FIN timing은 production mock 및 Experiment 1-13 configuration과 분리된다. client lifecycle policy, timeout, retry, pool capacity의 production 설정은 변경하지 않는다. diagnostic isolation을 위한 pool max connection 1은 test-local provider에만 적용한다.

## 고정 조건

- Reactor Netty 1.0.28, Spring Boot 2.7.9, Java 11 dependency line 유지
- FIFO default, maxIdle/maxLife/background eviction/custom predicate 미설정
- application retry, connection/response timeout, admission, workload, production mock 변경 금지
- localhost in-process test server와 single flight 8 cycles만 사용

## Event schema

모든 row는 JSON Lines로 다음 field를 사용한다.

```text
timestampEpochNanos, timestampEpochMillis, event, requestId, attemptId,
retryOfAttemptId, leaseId, channelId, localAddress, remoteAddress,
stage, thread, source
```

지원되는 event: `LOGICAL_REQUEST_CREATED`, `POOL_CONNECTION_ACQUIRED`, `REQUEST_PREPARED`, `REQUEST_SENT`, `REQUEST_BODY_SENT`, `MOCK_REQUEST_RECEIVED`, `MOCK_REQUEST_BODY_COMPLETED`, `MOCK_RESPONSE_STARTED`, `MOCK_RESPONSE_FINISHED`, `CLIENT_RESPONSE_RECEIVED`, `CLIENT_RESPONSE_BODY_COMPLETED`, `POOL_RELEASE_OBSERVED`, `MOCK_FIN_SENT`, `CLIENT_CHANNEL_INACTIVE`, `REQUEST_SUCCEEDED`, `REQUEST_FAILED`.

`POOL_ACQUIRE_REQUESTED`, direct `TRANSPORT_RETRY_*`, `CLIENT_CHANNEL_CLOSED`, `MOCK_RST_SENT`은 current public hook으로 직접 기록하지 못하면 `UNOBSERVABLE_WITH_CURRENT_HOOK`으로 남긴다.

## Gate 및 판정

- Gate A: `cycle-N-a`와 `cycle-N-b`가 같은 channel을 사용하고 release가 분리 기록된다.
- Gate B: FIN 뒤 inactive가 기록되고 `cycle-N-c`가 새 channel을 사용한다. 이 경로는 peer close가 acquire 전에 처리되므로 retry를 강제하지 않는다.
- Gate C: logical request당 mock handler 도달은 정확히 1회다.

성공은 8 cycle 모두 위 연결을 만족하고 production lifecycle 설정이 변경되지 않은 경우다. retry는 실제 attempt가 발생한 경우만 직접 결합한다. 이 test에서는 retry가 필요하지 않은 정상 close 경로라면 `NOT_ATTRIBUTABLE`로 기록하며, retry가 발생했다는 주장을 하지 않는다.

최종 판정은 `READY_FOR_LIFECYCLE_POLICY_DESIGN`, `INSUFFICIENT_LIFECYCLE_ATTRIBUTION`, `INVALID` 중 하나다. 성공하더라도 lifecycle remediation을 구현하거나 부하를 실행하지 않는다.

## Artifact

테스트는 `backend/doEngGameFlux/build/experiment-1-15/`에 다음을 생성한다.

```text
experiment-1-15-events.jsonl
experiment-1-15-cycles.json
experiment-1-15-summary.json
experiment-1-15-timeline.csv
experiment-1-15-validity.json
```

이는 build artifact이며 Git에 stage하지 않는다. 결과 문서에는 aggregate와 raw artifact location만 기록한다.

## Hard stop

LIFO, maxIdleTime, background eviction, maxLifeTime, application retry, server production keep-alive, VU load, MVC, dependency upgrade는 수행하지 않는다.
