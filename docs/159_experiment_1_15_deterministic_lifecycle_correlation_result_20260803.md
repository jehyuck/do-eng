# Experiment 1-15 — Deterministic Connection Lifecycle Correlation Result

작성일: 2026-08-03
상태: 부분 완료 — `INSUFFICIENT_LIFECYCLE_ATTRIBUTION`

## 목적과 범위

이 실행은 Experiment 1-13/1-14에서 남은 연결 lifecycle 질문을 좁은 test-only 경로에서 확인했다. 성능 부하, 운영 WebFlux 요청 경로, connection pool 설정, retry 정책, timeout, mock 운영 설정은 변경하지 않았다.

질문은 다음 하나였다.

> 단일 in-flight 조건에서 logical request → attempt → lease/channel → mock response finish → client response/body finish → pool release → mock peer close → 다음 acquire를 하나의 event stream으로 연결할 수 있는가?

기준 계획은 [Experiment 1-15 plan](158_experiment_1_15_deterministic_lifecycle_correlation_plan_20260803.md)이다.

## 실행 조건

- Reactor Netty 1.0.28 / Java 11 / Gradle 7.6.1 Docker build gate
- localhost test-only Reactor Netty server와 test-local provider (`maxConnections=1`)
- 8 cycles, cycle당 A(정상 요청) → B(정상 reuse 뒤 mock close) → C(다음 요청) 순서
- 항상 single-flight: 동시에 진행 중인 logical request는 하나
- test-only mock은 B response/pool release 이후 100ms 뒤 해당 server channel을 close했다.
- 실행 명령: `./gradlew test --tests com.example.doenggameflux.experiment.DeterministicConnectionLifecycleCorrelationTest --no-daemon`

Docker JDK 11에서 테스트는 `BUILD SUCCESSFUL`로 종료했다. 이는 성능 실험이 아니다.

## 원시 산출물

다음 build artifact는 Git에 stage하지 않았다.

- `backend/doEngGameFlux/build/experiment-1-15/experiment-1-15-events.jsonl`
- `backend/doEngGameFlux/build/experiment-1-15/experiment-1-15-cycles.json`
- `backend/doEngGameFlux/build/experiment-1-15/experiment-1-15-summary.json`
- `backend/doEngGameFlux/build/experiment-1-15/experiment-1-15-timeline.csv`
- `backend/doEngGameFlux/build/experiment-1-15/experiment-1-15-validity.json`

## 관측 방식과 attribution 경계

각 event에는 requestId, attemptId, leaseId, channelId, local/remote address, socket tuple, timestamp, thread, source를 JSONL로 남겼다.

Reactor Netty 1.0.28 public hook은 acquire 직전에 logical request를 직접 전달하지 않는다. 따라서 다음 표기를 명시적으로 사용했다.

```text
DIRECT_REQUEST_BINDING_NOT_AVAILABLE
DETERMINISTIC_SINGLE_FLIGHT_ATTRIBUTION_USED
```

이는 pool max 1과 strict single-flight라는 **테스트 격리 조건에만** 적용한 attribution이다. timestamp가 가까워서 request를 연결한 것이 아니며, 운영 부하 상황의 직접 correlation으로 일반화할 수 없다.

## 관찰된 사실

| 항목 | 결과 | 해석 범위 |
|---|---:|---|
| 완료 cycle | 8 / 8 | test harness 실행 자체는 정상 |
| A→B 정상 pooled reuse | 8 / 8 | peer close 전에는 같은 channel이 재사용됨 |
| B response 뒤 pool release | 8 / 8 | `POOL_RELEASE_OBSERVED`를 response/body finish와 분리해 수집 |
| mock FIN 및 server socket close 완료 | 8 / 8 | test-only mock의 peer close는 직접 기록됨 |
| B 뒤 C의 새 channel | 8 / 8 | close된 B channel은 다음 성공 요청의 최종 channel로 재사용되지 않음 |
| logical request당 mock handler | 24 request 모두 1회 | mock handler 중복 없음 |
| `CLIENT_CHANNEL_INACTIVE` | 0 / 8 | idle pooled client channel의 passive close를 현재 hook으로 직접 관측하지 못함 |
| request당 `REQUEST_SENT` | 24 request 모두 1회 | 이 경로에서 internal transport retry는 관측되지 않음 |

## 시간차 결과

다음 값은 localhost test harness의 event timestamp 차이이며 성능 SLA나 운영 latency가 아니다. 밀리초 표기는 정수 절삭값이다.

| 구간 | n | min / median / p95 / max (ms) | 판정 |
|---|---:|---:|---|
| T1 mock response finish → client response received | 8 | 0 / 0 / 0 / 0 | 결정적 attribution 범위에서 수집 |
| T2 mock response finish → client body completed | 8 | 0 / 0 / 1 / 1 | 결정적 attribution 범위에서 수집 |
| T3 mock response finish → pool release | 8 | 0 / 1 / 2 / 2 | 결정적 attribution 범위에서 수집 |
| T4 pool release → mock FIN | 8 | 98 / 99 / 100 / 100 | test가 의도한 100ms close schedule 확인 |
| T5 mock FIN → client channel inactive | 0 | NOT AVAILABLE (8건 결측) | client idle close event 미관측 |
| T6 mock FIN → 다음 acquire | 8 | 8 / 12 / 39 / 39 | test 순서상 관측; passive close 처리의 내부 인과 시간으로 단정 불가 |
| T7 acquire → request prepared | 0 | NOT AVAILABLE | public state callback의 causal boundary 미확보 |
| T8 request prepared → request sent | 0 | NOT AVAILABLE | state callback과 request callback의 순서가 안정적이지 않음 |
| T9 first failure → retry acquire | 0 | NOT AVAILABLE | first failure/retry 자체가 이 경로에서 관측되지 않음 |

## request–attempt–lease 구분 결과

- logical request와 test attempt는 각각 24개와 24개로 분리해 기록했다. attempt는 각 logical request의 `A1` 한 번뿐이었다.
- `leaseId`는 channel ID와 acquire sequence를 조합해 기록했다.
- B 요청의 lease/channel과 C 요청의 최종 channel은 8 cycle 모두 달랐다.
- acquire 이전에 request를 직접 bind하는 공개 API가 없으므로, `ACQUIRED` event의 requestId/attemptId는 strict single-flight attribution이다. `DIRECT_REQUEST_BINDING_NOT_AVAILABLE`를 유지한다.

## response finish–release 시간차

mock response finish, client response receive, client body completion, pool release는 모두 별도 event로 남았다. T3는 8회 모두 수집됐고 median 1ms였다. 이 값은 테스트 환경에서 response completion과 pool release가 구분되는지 확인하는 용도일 뿐, 운영 시스템의 release 지연을 뜻하지 않는다.

## peer close–channelInactive 시간차

mock은 8회 모두 FIN send와 server socket close completion을 남겼다. 그러나 client channel handler와 `ConnectionObserver.DISCONNECTING` 어느 쪽에서도 해당 B request의 `CLIENT_CHANNEL_INACTIVE`가 기록되지 않았다.

따라서 `peer close → client channel inactive` 시간차는 `NOT AVAILABLE`이다. mock close event와 다음 C 요청의 새 channel만으로 client close callback의 전달 시점이나 close initiator를 추정하지 않는다.

## internal retry 판정

`NOT_ATTRIBUTABLE`

이번 24 logical request는 모두 `REQUEST_SENT` 1회와 mock handler arrival 1회였다. `REQUEST_FAILED`, 두 번째 send, direct `TRANSPORT_RETRY_*` event가 없으므로 retry가 발생했다고도, retry가 발생하지 않을 일반 규칙이라고도 주장하지 않는다.

## mock handler 중복 여부

없음. 24개의 unique requestId 모두 mock handler count가 정확히 1이었다. 이 test 경로에서 retry/duplicate send가 mock handler 중복으로 나타나지 않았다.

## 최종 판정

`INSUFFICIENT_LIFECYCLE_ATTRIBUTION`

정상 reuse, mock close, 다음 신규 channel, response/body/release 분리는 재현했다. 하지만 요구한 결정적 pipeline의 핵심 중 `peer close → client channel inactive` 직접 event와 internal retry lifecycle은 0회 관측됐다. 따라서 현재 evidence만으로 FIFO/LIFO, idle eviction, retry 등의 lifecycle remediation을 설계하거나 적용할 근거는 충분하지 않다.

## 다음에 허용되는 작업

새 성능 실험이나 remediation 없이, **passive idle close를 client channel에서 직접 bind할 수 있는 test-only 관측 지점 하나**를 사전 등록해 diagnostic 1회로 검증하는 작업만 허용된다.

## 금지되는 작업

- LIFO/FIFO 변경
- `maxIdleTime`, `maxLifeTime`, background eviction 변경
- connection pool, timeout, retry, admission, scheduler 변경
- 운영 mock 또는 business path 변경
- VU/load/MVC 실행
