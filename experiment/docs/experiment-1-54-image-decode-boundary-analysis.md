# Exp154 Image Decode Boundary Analysis

## Current Path

`POST /game/face`의 현재 성공 경로는 다음과 같다.

```text
AiGameController.requestFaceAi
→ requestAi
→ TOKEN dispatcher
→ AI dispatcher
→ completeIfMatched
→ ImagePayloadDecoder.decodeDataUrlOrBase64
→ DBComponentHttp.saveData
→ STORAGE dispatcher
→ HttpMissionImageStorage 또는 S3MissionImageStorage
→ MissionDatabaseService
```

코드상 AI 요청에는 DTO의 원본 `image` 문자열이 전달된다. AI가 성공 결과를 반환하고 `result=true`인 경우에만 decode가 실행된다. `result=false`인 경우 decode와 저장 경계는 실행되지 않는다.

## Current Scheduler Boundary

`AiGameController.completeIfMatched`는 다음 경계를 사용한다.

```java
Mono.fromCallable(() -> ImagePayloadDecoder.decodeDataUrlOrBase64(originalImage))
    .subscribeOn(Schedulers.parallel())
```

따라서 Base64 decode는 요청별 executor가 아니라 애플리케이션 전체에서 공유되는 Reactor `Schedulers.parallel()`의 worker에서 시작된다. `parallel()`의 실제 worker 수는 런타임 CPU 설정에 의해 결정되며 현재 코드에서 별도로 고정하지 않는다.

확인된 구분은 다음과 같다.

- HTTP 요청·WebClient callback: Reactor Netty event-loop 경계
- Base64 decode: 공유 `Schedulers.parallel()` 경계
- Storage dispatcher: 별도 Sink consumer와 단계별 concurrency 경계. decode 전용 scheduler는 아님
- `Schedulers.boundedElastic()`: 현재 HTTP `completeIfMatched` decode 경로에는 사용되지 않음. 기존 다른 경로의 사용과 혼동하지 않는다.
- S3 async upload: `S3AsyncClient`의 future callback을 `Mono.fromFuture`로 연결하며 decode scheduler를 별도로 만들지 않는다.

현재 소스에는 `publishOn`, decode 전용 bounded scheduler, 요청마다 생성하는 executor가 없다.

## Fixture Facts

기존 실험 runner와 `mission-load.js`가 지정하는 대표 fixture는 `image/arc.jpg`다. 현재 checkout에서 확인한 값은 다음과 같다.

- path: `image/arc.jpg`
- original bytes: `265745`
- Base64 characters: `354328`
- `data:image/jpeg;base64,` prefix 포함 문자열: `354351` characters
- SHA-256: `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`

Base64 문자열 길이는 원본 byte 수보다 커지며, 이는 decode 단계의 입력 보유량과 결과 `byte[]` 보유량을 함께 고려해야 함을 의미한다. 이 문서에서는 별도 small/large fixture를 만들거나 성능 결과를 산출하지 않는다.

## Decode Characteristics

`ImagePayloadDecoder`는 다음 작업을 동기적으로 수행한다.

1. null/blank 입력 검증
2. 첫 comma 이후의 encoded 문자열 선택
3. `Base64.getDecoder().decode(encoded)`로 새 `byte[]` 생성

코드에서 확인되는 메모리 경계는 다음과 같다.

- 원본 request DTO의 image `String`은 AI 요청과 decode 완료까지 참조될 수 있다.
- Data URL이면 comma 이후를 얻기 위한 별도 `String` 값이 만들어진다.
- decode 결과로 별도 `byte[]`가 만들어지고 `StorageDispatchRequest`가 이를 storage 단계까지 보유한다.
- 정확한 JVM heap peak, GC, 객체 생존 시간, 문자열 내부 표현은 현재 계측 자료만으로 확인되지 않는다.

`result=false` 경로에서는 위 decode 작업이 발생하지 않는다는 점은 코드로 확정된다.

## Minimal Measurement

`ImagePayloadDecoderTest`가 Data URL과 raw Base64 입력, 빈 입력 예외를 검증한다. 그러나 단일 decode 시간, 반복 decode 분포, heap allocation 또는 worker queue 대기시간을 측정하는 테스트·raw 결과는 현재 자료에서 확인되지 않는다.

```text
MINIMAL_MEASUREMENT: NOT RUN
MEASUREMENT_RESULT: NOT AVAILABLE
```

따라서 현재 문서에서 CPU-bound 여부의 정량 임계값이나 dedicated scheduler의 이득을 주장하지 않는다. JMH를 추가하거나 HTTP A/B를 실행하지 않는다.

## Candidate Evaluation

### Candidate A — 현재 `Schedulers.parallel()` 유지

**ACCEPT (현재 기준선 유지)**

현재 decode가 Netty event-loop에서 직접 동기 실행되지 않도록 분리되어 있다는 구현 사실이 있다. 별도 executor를 생성하지 않고, 애플리케이션 공용 CPU scheduler를 사용한다. 단, parallel scheduler가 다른 CPU 작업과 공유되므로 포화·tail 영향은 아직 측정되지 않았다.

### Candidate B — dedicated bounded decode scheduler

**REJECT (현재 단계에서 채택하지 않음)**

전용 bounded scheduler가 필요한지 판단할 직접 계측이 없다. 도입하면 scheduler 크기·queue·shutdown 정책이라는 추가 핵심 변수가 생긴다. 현재 Exp154 사전 분석 범위에서 이를 임의로 설계하거나 production에 추가하지 않는다.

### Candidate C — decode를 Storage Dispatcher 내부로 이동

**REJECT**

Storage dispatcher는 외부 I/O concurrency 경계다. decode를 그 안으로 옮기면 CPU 작업과 storage I/O의 concurrency가 결합되고, queue가 Base64 문자열 또는 decoded `byte[]`를 보유하는 시간과 메모리 특성이 달라진다. 단순한 코드 이동만으로 동일한 경계를 유지한다고 볼 수 없다.

## Selected Hypothesis

현재 증거에 기반한 단일 선택은 다음이다.

```text
H-A: Base64 decode는 현재처럼 공유 Schedulers.parallel()에서 수행하는 경계를 기준선으로 유지한다.
```

이는 `parallel()`이 최적이라는 성능 결론이 아니다. 별도 bounded scheduler로 전환할 근거가 현재 계측에 없으므로, 후속 검증이 승인될 때 비교할 기준 경계를 고정한 것이다.

## Controlled Variables

후속 측정이 별도로 승인될 경우에도 다음은 고정해야 한다.

- 동일 `image/arc.jpg` fixture와 SHA-256
- 동일 Data URL prefix 및 payload 생성 방식
- 동일 AI 결과 조건(`result=true` 경로와 `result=false` 경로를 혼동하지 않음)
- 동일 WebFlux request contract, timeout, external mock 조건
- 동일 TOKEN/AI/STORAGE/DB 경로
- 동일 application CPU·memory 제한
- 동일 dispatcher 및 provider 설정
- decode scheduler 외 다른 production 변경 금지

측정 대상으로는 decode duration, 반복 decode duration, 결과 `byte[]` 크기, 예외 입력 동작을 우선 고려한다. scheduler queue 대기, CPU, allocation은 직접 계측하지 않는 한 `NOT AVAILABLE`로 남긴다.

## Required Validation

현재 단계에서 실행하지 않는다. 후속 실행이 승인된다면 최소한 다음을 별도 계획으로 등록해야 한다.

- 기존 `ImagePayloadDecoderTest` 통과
- 동일 fixture의 decode 결과 길이·checksum 확인
- decode 예외 입력 동작 확인
- decode 구간과 storage 구간의 계측 분리
- shared parallel scheduler와 dedicated bounded scheduler를 한 번에 하나의 변수로 비교

## Non-Goals

- Sink Dispatcher 성능 판정
- Reactor Netty provider pool 조정
- Admission Gate 변경
- S3 또는 DB 구현 변경
- MVC 비교
- 전체 WebFlux 성능 결론
- 이미지 리사이즈·재인코딩·압축 정책 결정

## Claim Boundary

현재 자료로 허용되는 주장은 다음뿐이다.

- 성공한 HTTP 요청의 Base64 decode는 `Schedulers.parallel()` 경계에서 실행된다.
- decode는 동기 `Base64.getDecoder().decode` 호출이며 결과 `byte[]`를 만든다.
- decode 결과는 Storage Dispatcher를 거쳐 storage와 DB 단계로 이어진다.
- 현재 직접 측정된 decode CPU·allocation·scheduler queue 수치는 없다.

다음은 주장할 수 없다.

- `Schedulers.parallel()`이 최적이다.
- dedicated bounded scheduler가 더 빠르거나 안전하다.
- decode가 현재 시스템의 병목이다.
- decode를 Storage Dispatcher로 옮겨야 한다.

## Readiness Decision

```text
EXP154_READY
```

현재 구현 경계와 단일 후보가 코드로 명확하며, 후속 검증 시 필요한 변수를 분리할 수 있다. 이는 실험 결과나 성능 개선 판정이 아니며, production source·scheduler·dispatcher는 변경하지 않았다.
