# Experiment 1-16 — Close/Acquire Race Attribution Result

작성일: 2026-08-03
상태: 완료 — `READY_FOR_LIFECYCLE_POLICY_DESIGN`

## 목적과 범위

Experiment 1-15는 server close completion 뒤에 C 요청을 시작했으므로 close/acquire race를 만들지 못했다. 이번 실행은 test-only server가 close를 **시작하는 순간** C 시작 barrier를 열어, close completion을 기다리지 않고 C logical request를 생성했다.

성능 부하, production WebFlux path, pool/lifecycle/timeout/retry/admission 설정, 운영 mock은 변경하지 않았다.

## 실행 조건

- Reactor Netty 1.0.28 / Java 11 / Gradle 7.6.1 Docker test
- localhost test-only server, test-local provider `maxConnections=1`, strict single-flight
- 8 cycle 고정
- A 정상 요청·release → B 정상 reuse·release → B close initiation과 C start barrier를 동시 발생
- mock close future, client close future **완료를 기다리지 않고** C 시작
- 실행 명령: `./gradlew test --tests com.example.doenggameflux.experiment.CloseAcquireRaceAttributionTest --no-daemon`

테스트는 `BUILD SUCCESSFUL`로 종료했다.

## 원시 산출물

다음 build artifact는 Git에 stage하지 않았다.

- `backend/doEngGameFlux/build/experiment-1-16/experiment-1-16-events.jsonl`
- `backend/doEngGameFlux/build/experiment-1-16/experiment-1-16-cycles.json`
- `backend/doEngGameFlux/build/experiment-1-16/experiment-1-16-summary.json`
- `backend/doEngGameFlux/build/experiment-1-16/experiment-1-16-timeline.csv`
- `backend/doEngGameFlux/build/experiment-1-16/experiment-1-16-validity.json`

## 관측 구현

`HttpClient.doOnChannelInit`에서 client channel별로 한 번만 다음을 등록했다.

- `CLIENT_CLOSE_LISTENER_REGISTERED`
- `channel.closeFuture()` listener → `CLIENT_CLOSE_FUTURE_COMPLETED`
- channel handler → `CLIENT_CHANNEL_INACTIVE`, `CLIENT_CHANNEL_UNREGISTERED`

실행 중 close listener 등록은 9회였고, 서로 다른 client channel 9개에 정확히 한 번씩 등록됐다. B old channel 8개는 모두 closeFuture completion을 남겼다.

public acquire hook에는 logical request가 직접 전달되지 않는 제약이 남아 있어 다음 표기를 유지한다.

```text
DIRECT_REQUEST_BINDING_NOT_AVAILABLE
DETERMINISTIC_SINGLE_FLIGHT_ATTRIBUTION_USED
```

이는 pool 1개·strict single-flight의 test isolation에서만 사용했다.

## race 성립 확인

8/8 cycle에서 C start signal과 C logical request 생성은 `MOCK_CLOSE_FUTURE_COMPLETED`보다 먼저 발생했다.

| 구간 | n | min / median / p95 / max (ms) |
|---|---:|---:|
| mock close initiated → C logical request created | 8 | 0.342 / 0.441 / 1.126 / 1.126 |
| C logical request created → mock close future completed | 8 | 0.073 / 0.182 / 15.667 / 15.667 |
| mock close future completed → client close future completed | 8 | 0.468 / 0.694 / 14.681 / 14.681 |
| client close future completed → C acquire | 8 | 5.960 / 7.940 / 13.870 / 13.870 |
| C acquire → C request sent | 8 | 0.450 / 1.175 / 1.595 / 1.595 |

이는 localhost test-only event timestamp이며 운영 latency 수치가 아니다. 특히 C logical request가 close completion보다 먼저 생성됐지만, 실제 pool acquire는 client closeFuture completion 뒤에 일어났다.

## cycle별 분류

| 분류 | cycle |
|---|---:|
| `POOL_FILTERED_CLOSED_CHANNEL` | 8 |
| `OLD_CHANNEL_ACQUIRED_THEN_RETRIED` | 0 |
| `OLD_CHANNEL_ACQUIRED_AND_FAILED` | 0 |
| `POST_SEND_CLOSE` | 0 |
| `NOT_ATTRIBUTABLE` | 0 |

8개 모두에서 C는 B old channel을 acquire하지 않았고, 신규 channel에서 최초 send 후 성공했다. C final channel은 B channel과 8/8 달랐다.

## internal retry 판정

`NOT_OBSERVED` (8/8)

C의 old channel acquire, pre-send failure, second acquire 조합이 없었다. 따라서 retry-once가 발생했다는 주장을 하지 않으며, direct transport retry hook도 이번 public instrumentation에는 없다.

## mock handler 중복 여부

없음. A/B/C 24개 unique requestId는 모두 mock handler 도달 1회였다. C request도 8/8 한 번만 도달했다.

## 최종 판정

`READY_FOR_LIFECYCLE_POLICY_DESIGN`

이 고정 race에서는 close initiation과 C logical request가 실제로 겹쳤고, client closeFuture·old/new channel 선택·request send·mock handler 도달을 cycle 단위로 귀속했다. 관측된 메커니즘은 **client close 처리 후 pool이 closed old channel을 C acquire에서 제외하고 신규 channel을 제공한 것**이다.

이 판정은 Reactor Netty 1.0.28 localhost test harness의 하나의 close/acquire 경계에 한정된다. Experiment 1-12/1-13의 production-like load failure를 이 결과 하나로 완전히 설명하거나 특정 remediation을 바로 적용한다는 뜻은 아니다.

## 다음 단계에서 허용되는 작업

이번 evidence를 전제로 lifecycle policy 후보를 **문서로 설계·사전등록**하는 작업은 허용된다. LIFO, idle eviction, timeout, retry, pool 변경이나 새로운 부하 실행은 자동으로 시작하지 않는다.
