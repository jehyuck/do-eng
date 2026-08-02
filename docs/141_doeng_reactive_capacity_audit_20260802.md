# DoEng Reactive Capacity Audit

## 확인한 source

- `AiGameController`
- `AiOutboundAdmissionGate`, `AdmissionProperties`, `AiCapacityExceededException`
- `AiCapacityExceptionHandler`
- `TokenComponent`, `DBComponentHttp`, `MissionDatabaseService`
- `HttpMissionImageStorage`, `ImagePayloadDecoder`
- `ExternalHttpClientConfig`, `ExternalServiceProperties`, `StageObservation`

## 전체 request path

`POST /game/face`는 `@RequestBody Mono<ImageRequestDto>`를 받아 Authorization과 `X-Mission-Run-Id`를 확인한다. 이후 `Mono.zip(image, TOKEN)` → AI WebClient → 정답일 때 Base64 decode → storage upload → R2DBC DB save → HTTP 200 응답 순서다. 현재 outer gate는 per-outbound scope가 아니면 이 pipeline 전체를 감싼다.

## blocking 위험

요청 경로에서 `.block`, `.blockFirst`, `.blockLast`, `Thread.sleep`, `CompletableFuture.join`, `Future.get`, `RestTemplate`, 명시적 blocking DB/file I/O는 확인되지 않았다. `ImagePayloadDecoder`는 `Mono.fromCallable(...).subscribeOn(Schedulers.parallel())`로 실행되므로 event-loop 직접 실행은 피하지만 scheduler queue와 CPU 비용은 직접 측정되지 않아 `NEEDS MEASUREMENT`다. WebSocket/AWS legacy 코드의 detached subscribe는 이 REST path 밖이므로 별도 사실로 보존한다.

## scheduler 사용

Base64 decode가 Reactor `parallel` scheduler로 이동한다. 해당 scheduler의 queue length, worker 대기, CPU 점유는 현재 raw metric에 없다. 이것만으로 blocking 원인을 단정하지 않는다.

## request body subscription 시점

Controller는 body를 `Mono<ImageRequestDto>`로 받으며 pipeline subscription 시점에 body가 소비된다. 현재 admission gate가 outer pipeline을 감싸면 ENFORCE 거절 시 action supplier와 pipeline subscription이 발생하지 않아 body, TOKEN, AI, STORAGE, DB가 시작되지 않는 계약을 테스트해야 한다.

## timeout 계약

HttpClient connect timeout은 2 s, response timeout은 10 s, pool pending acquire timeout은 10 s, load client timeout은 10 s다. 전체 request에 단일 Reactor `.timeout`이 없고 nested timeout의 누적/경계가 직접 측정되지 않아 `NEEDS MEASUREMENT`로 남긴다. 이번 작업에서는 timeout을 변경하지 않는다.

## retry 계약

REST request path에서 자동 retry/operator와 `onErrorResume` 기반 retry는 확인되지 않았다. WebClient response error는 실제 downstream 상태로 mapping되며, admission exception만 별도 handler가 처리한다.

## cancellation 전파

WebClient와 R2DBC publisher는 reactive cancellation을 전파할 수 있다. gate는 `doFinally`에서 completion/error/cancel을 모두 release해야 하며, 이번 구현에서 cancellation counter와 leak을 직접 검증한다.

## WebClient pool topology

`ExternalHttpClientConfig`는 shared/token/ai/storage provider를 만들고 `DOENG_EXTERNAL_POOL_MODE=SHARED`이면 TOKEN, AI, STORAGE WebClient가 shared provider를 사용한다. Experiment 1-9는 shared max 400, pending 800을 고정하며 pool tuning이나 isolation rerun을 하지 않는다.

## capacity를 잃는 확인된 요인

현재 코드와 기존 결과로 확인되는 것은 non-blocking path 자체가 전체 concurrency budget을 제공하지 않았고, shared outbound pool과 pending queue가 전체 요청 pressure를 제한한다는 구조적 사실이다. 실제 capacity 손실의 단일 원인(네트워크, decode CPU, DB, pool acquire)을 이 감사만으로 확정하지 않는다.

## 근거가 없어 변경하지 않은 항목

pool 증설/분리, timeout 변경, retry/fallback, scheduler 변경, Base64 방식 변경, R2DBC 변경, HTTP/2, queue/bulkhead 라이브러리 도입은 직접 근거가 없어 변경하지 않는다.

## 구현 변경

이번 실험의 허용 변경은 admission mode enum, 전체 path observation/enforcement metric, explicit admission 503 + `Retry-After: 1`, 그리고 이에 대한 lazy subscription/release/CAS race 테스트뿐이다. business chain의 순서와 외부 호출 semantics는 유지한다.
