# do-eng MVC400 및 corrected WebFlux 기술 종결

## 1. 문제 정의

do-eng의 이미지 게임 요청은 webcam image를 수신한 뒤 외부 AI service, image storage, database를 순서대로 거친다. 따라서 요청이 외부 I/O 응답을 기다리는 시간이 길어질수록 application 내부의 동시 처리 여유가 줄어들 수 있다.

이번 검증의 질문은 다음과 같았다.

1. 동일한 `SERVICE3S` request contract에서 blocking MVC reference와 corrected WebFlux implementation은 어떤 차이를 보이는가?
2. 외부 I/O 대기, database 접근, image storage, CPU decoding을 현재 source가 어떻게 구성하고 있는가?
3. 어느 결과를 확인된 사실로 말할 수 있고, 어느 결과는 아직 원인으로 확정할 수 없는가?

특정 framework가 항상 더 빠르다는 것을 증명하는 실험은 아니다.

이 문서는 documentation-only 결과다. 이 문서를 작성하기 위해 workload, Docker benchmark, JFR capture 또는 production change를 수행하지 않았다.

## 2. Evidence 및 시간축

- Repository: `jehyuck/do-eng`
- Base source HEAD: `407e380f0fdb91a167685ebc8300b544039b3d75`
- Documentation branch: `docs/doeng-technical-closure-20260813`
- Image-payload evidence commit: `e3ac034ec26f1c7f14dd3b09419cd7d012249863`
- Image-payload document: `docs/194_webflux_image_payload_characterization.md`
- SERVICE3S closure: `docs/104_webflux_mvc_final_experiment_closure.md`
- Fixed-periodic plan: `docs/125_fixed_periodic_frame_matrix_plan.md`
- Image-payload open Issue: GitHub Issue #4

2023 material은 project implementation과 당시 경험을 설명한다. 2026 material은 controlled 또는 synthetic verification과 evidence boundary를 기록한다. 2026 결과를 2023 production performance outcome처럼 표현하지 않는다.

## 3. 관찰된 문제와 원인 분석

### 3.1 외부 AI I/O 대기

문제는 AI response를 기다리는 시간이 request path에 포함된다는 점이다. 이는 AI latency 자체를 줄이는 문제와는 다르며, 대기 중 servlet worker를 계속 점유하는 구조인지가 application capacity에 영향을 줄 수 있다.

현재 source에는 `AiGameController`와 `TokenComponent`가 `WebClient`를 사용하고, `ExternalHttpClientConfig`가 token/AI/storage client와 connection provider를 구성한다. 따라서 corrected WebFlux의 선택 이유는 AI를 더 빠르게 만드는 것이 아니라, 대기 구간을 reactive HTTP composition으로 표현하기 위해서다.

### 3.2 Database 접근

요청 경로에는 database I/O도 포함된다. corrected WebFlux source는 `R2DBC` dependency와 reactive repository/service path를 사용한다.

다만 이번 closure의 Evidence만으로 R2DBC 자체의 독립적인 latency 개선 효과나 database가 단일 root cause였다고 말할 수는 없다. DB path는 구조적 선택으로 기록하고, 정량적 인과는 별도 실험의 범위로 남긴다.

### 3.3 Image storage

image 결과 저장은 요청 경로의 downstream 단계다. source에는 `MissionImageStorage` abstraction과 `HttpMissionImageStorage`, `S3MissionImageStorage` 구현이 있으며, `DBComponentHttp`에서 reactive chain으로 storage 결과를 다음 단계에 연결한다.

이 구조가 storage service의 latency 자체를 줄였다고 주장하지 않는다. storage 대기와 connection pressure가 요청 경로의 일부라는 점만 확인한다.

### 3.4 Reactive composition과 CPU 작업 분리

`AiGameController`, `DBComponentHttp`, `MissionDatabaseService`에서 `Mono`/`Flux`와 `flatMap`을 사용해 AI → storage → DB 단계를 연결한다. `ExternalHttpClientConfig`는 token/AI/storage별 `WebClient`와 connection provider를 제공한다.

image decode와 같은 CPU 작업에는 source에서 `Schedulers.parallel()` 사용이 확인된다. 일부 file upload path에는 `Schedulers.boundedElastic()`도 사용된다. 이는 event-loop에서 CPU 또는 blocking 성격의 작업을 분리하려는 구조적 의도이지만, 이 closure는 해당 분리의 성능 개선량을 별도로 측정하지 않았다.

## 4. 해결 방식과 corrected WebFlux 구조

검증 대상 구조는 다음과 같다.

```text
요청 수신
  → WebClient 기반 token/AI 호출
  → reactive image decode / payload 처리
  → WebClient 또는 S3 async storage
  → R2DBC 기반 DB 처리
  → completion 응답
```

구조 선택은 다음 문제에 대응한다.

| 문제 | source에서 확인한 구조 | 이번 closure에서의 의미 |
|---|---|---|
| 외부 AI 응답 대기 | `WebClient` | blocking worker 점유를 줄이기 위한 reactive composition |
| DB I/O | `R2DBC` reactive path | DB 대기를 reactive chain에 포함 |
| image storage I/O | `MissionImageStorage`, `HttpMissionImageStorage`, `S3MissionImageStorage` | storage 단계를 downstream publisher로 연결 |
| 단계 조합 | `Mono`/`Flux`, `flatMap` | AI → storage → DB 순서를 publisher로 표현 |
| CPU/image 처리 | `Schedulers.parallel()` | event-loop와 CPU 작업을 분리하려는 구조 |
| 외부 connection 관리 | token/AI/storage별 `WebClient`와 provider | shared pressure를 관찰하고 분리 가능성을 둔 구조 |

위 표는 source 구조에 대한 설명이다. 각 항목이 단독으로 성능 개선을 만들었다고 확대하지 않는다.

## 5. MVC400을 최종 비교군으로 사용한 이유

초기 MVC200 결과만으로 WebFlux 우위를 결론내리지 않았다. Historical VU120 3-arm evidence에서 MVC worker-capacity sensitivity가 관찰됐고, worker 200과 400에서 결과가 달라졌다. 따라서 MVC400을 사용해 기본 worker capacity를 상향한 reference를 구성한 뒤, 동일한 `SERVICE3S` contract에서 corrected WebFlux와 다시 비교했다.

정리하면 다음과 같다.

```text
MVC400 = 기본 조정이 반영된 비교 reference
MVC400 != 모든 MVC 설정을 최적화한 상한 구성
```

이 선택은 MVC를 의도적으로 불리하게 만들기 위한 것이 아니라, 초기 MVC 결과가 worker capacity에 민감했는지 확인하고 비교 조건을 명확히 하기 위한 것이다.

## 6. SERVICE3S 검증 조건

- 160 active users
- 3000ms interval
- feedback-coupled mission/reconnect workload
- AI delay 2000ms
- storage delay 100ms
- application 2 CPU / 3 GiB
- HTTP pool 400
- DB pool 10
- JVM Xms 512m / Xmx 2048m

동일한 frozen request flow, fixture, load contract, resource contract, storage condition, HTTP settings, DB pool 및 MariaDB image를 pair 안에서 유지했다.

## 7. 검증 결과

기록된 three-run median은 다음과 같다.

| Metric | Corrected WebFlux | MVC400 |
|---|---:|---:|
| Success rate | 100% | 55.0762% |
| Successful RPS | 51.457143 | 28.571429 |
| p95 | 3092ms | 8339ms |

Canonical evidence에서 derived ratio는 median successful throughput 기준 약 `1.80x`, MVC400/WebFlux p95 ratio 기준 약 `2.70x`다. `2.70x throughput`으로 표현하지 않는다.

허용되는 결과 문장은 다음과 같다.

> 고정된 `SERVICE3S` contract에서 corrected WebFlux가 MVC400 reference보다 높은 completion과 successful-throughput 결과를 기록했다. 이 결과는 tested implementation/configuration envelope에 한정된다.

WebFlux가 AI service 자체를 빠르게 만들었다거나, MVC400이 모든 MVC configuration보다 느리다거나, WebFlux가 보편적으로 우월하다고 말할 수는 없다.

## 8. Fixed-periodic cadence 결과

Fixed-periodic evidence family는 SERVICE3S feedback-coupled workload와 별개다.

- 3000ms: tested contract에서 기록된 stable operating region
- 1000ms: tested condition에서 degradation 관찰
- 500ms: recorded matrix에서 `LOAD_GENERATOR_LIMITED`

따라서 1000ms degradation의 단일 원인은 `NOT_ESTABLISHED`이고, 500ms 결과를 application capacity exceeded로 표현하지 않는다.

## 9. Connection 및 transport 결과

P400 evidence에서는 shared outbound active/pending pressure, TOKEN/AI failure 및 `PrematureClose` observation이 함께 나타났다.

현재 분류는 다음과 같다.

```text
CONNECTION_POOL_TRANSPORT_FAMILY = CLOSED_WITH_LIMITATIONS
```

정확한 failure position, stage dominance, pool optimum 또는 pool 변경의 causal gain은 확정하지 않았다.

## 10. Image-payload 상태

`docs/194_webflux_image_payload_characterization.md`의 단일 WebFlux profile은 유효하다. JFR에서 payload 관련 CPU/allocation activity가 반복적으로 관찰됐지만, 현재 상태는 다음과 같다.

```text
PROFILE VALID
VERDICT NOT YET CLOSED
```

따라서 `PAYLOAD_COST_MATERIAL_CANDIDATE`를 최종 material verdict로 확정하지 않고, MVC collapse의 root cause나 optimization effect로도 확정하지 않는다.

## 11. Problem–Cause–Solution–Evidence matrix

| 문제 | 원인 분석 | 해결 방식/판단 | Evidence | 상태 |
|---|---|---|---|---|
| 외부 AI I/O 대기 | I/O wait가 request path에 포함됨 | `WebClient` 기반 non-blocking composition | source, SERVICE3S comparison | 구조는 확인, 단독 인과 gain은 미확정 |
| DB I/O 대기 | reactive request path에 DB 접근 존재 | `R2DBC` path | source | 구조는 확인, 독립 성능 효과는 미확정 |
| image storage downstream | storage upload가 완료 경로에 포함됨 | `MissionImageStorage` 및 reactive storage adapter | source, storage condition | 구조는 확인, storage 단독 병목은 미확정 |
| 단계 조합과 외부 connection pressure | token/AI/storage가 반복 요청 경로에 함께 존재 | 단계별 `WebClient`/provider와 reactive `flatMap` composition | P400 evidence | `CLOSED_WITH_LIMITATIONS` |
| image decode CPU/allocation | JFR에서 관련 activity 관찰 | `Schedulers.parallel()` 사용 구조 확인 | `WEBFLUX-IMAGE-PAYLOAD-PROFILE-002` | `PROFILE VALID`, verdict 미종결 |
| MVC reference 공정성 | Historical VU120에서 worker capacity sensitivity 관찰 | MVC400을 조정된 reference로 재비교 | historical evidence, SERVICE3S | 비교 조건 설명 완료 |
| 1초 cadence degradation | 단일 원인 미확정 | 3초 stable region을 운영 판단 경계로 기록 | fixed-periodic evidence | `NOT_ESTABLISHED` |
| 0.5초 결과 | load-generator 측 제한 | application capacity로 재분류하지 않음 | fixed-periodic matrix | `LOAD_GENERATOR_LIMITED` |

이 표에서 `해결 방식`은 구조 선택 또는 판단 경계이며, 모든 행이 성능 개선을 증명하는 것은 아니다.

## 12. 현재 종결 상태

- MVC baseline/reference: `CLOSED` for the recorded evidence envelope
- Corrected WebFlux baseline/reference: `CLOSED` for the recorded evidence envelope
- MVC400 versus corrected WebFlux SERVICE3S: `CLOSED` with claim boundaries
- Fixed-periodic cadence: `CLOSED` as a tested evidence family
- Connection/transport: `CLOSED_WITH_LIMITATIONS`
- Image-payload software headroom: `PROFILE VALID`, `VERDICT NOT YET CLOSED`

## 13. 제한과 다음 판단

- 이번 문서 수정으로 workload나 raw Evidence를 새로 만들지 않았다.
- WebFlux의 우위는 고정된 `SERVICE3S` contract의 비교 결과에 한정된다.
- MVC worker exhaustion, connection-pool pressure, AI capacity, image payload 중 하나를 단독 root cause로 확정하지 않았다.
- R2DBC, storage adapter, CPU scheduler 각각의 독립적인 causal gain은 별도 실험 없이는 주장하지 않는다.
- 후속 작업이 필요하다면 원인별로 하나의 변인만 통제하는 controlled experiment를 별도 승인받아야 한다.

## 14. 면접 설명 anchor

- 문제는 외부 I/O가 포함된 요청 경로와 MVC worker capacity sensitivity였다.
- 원인 분석에서는 관찰된 압력과 확정된 인과를 분리했다.
- 해결 방향은 AI/DB/storage를 reactive composition으로 연결하고, CPU 작업을 별도 scheduler로 분리하는 구조였다.
- MVC400은 초기 MVC 결과의 worker-capacity sensitivity를 확인하기 위한 공정한 reference였다.
- corrected WebFlux는 AI를 빠르게 만든 것이 아니라, tested waiting condition에서 더 높은 completion을 기록했다.
- `1.80x`는 successful throughput ratio이고 `2.70x`는 p95 ratio다.
- `PROFILE VALID`는 payload 관찰이 유효하다는 뜻이며 최종 root cause verdict가 아니다.
