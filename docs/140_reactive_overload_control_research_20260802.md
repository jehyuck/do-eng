# Reactive Overload Control Research

## 확인한 공식 자료

- [Spring WebFlux 공식 개요](https://docs.spring.io/spring/reference/7.1-SNAPSHOT/web/webflux/new-framework.html): WebFlux는 non-blocking 서버와 reactive programming 모델을 제공하지만 애플리케이션 전체의 동시성 예산을 자동으로 정하지 않는다.
- [Reactor Netty HTTP client 공식 문서](https://projectreactor.io/docs/netty/release/reference/http-client.html): connection provider는 대상별 pool을 만들고 active/max/pending/pending acquire time을 관측한다.
- [Reactor Netty 1.0.28 API](https://projectreactor.io/docs/netty/1.0.28/api/reactor/netty/resources/ConnectionProvider.ConnectionPoolSpec.html): `maxConnections` 이후 acquire가 pending으로 들어가며 `pendingAcquireMaxCount`가 대기 등록 상한을 정한다.
- [AWS Builders' Library load shedding](https://aws.amazon.com/cn/builders-library/using-load-shedding-to-avoid-overload/): overload 보호는 부하가 급증하는 경계를 찾아 false-positive rejection을 줄이면서 시스템의 유용한 처리량과 latency를 보호하는 접근이다.
- [AWS Builders' Library dependency isolation](https://aws.amazon.com/about-aws/whats-new/2020/10/new-amazon-builders-library-article-scale-inversion/): 외부 dependency별 격리는 한 dependency의 concurrency가 전체 요청을 잠식하지 않게 하는 별도 설계다.

## WebFlux가 제공하는 것

WebFlux와 Reactor는 non-blocking publisher, subscription 지연, cancellation 전파, event-loop 기반 서버 실행 모델을 제공한다. 따라서 action을 `Mono.defer` 안에 두면 요청이 실제로 구독될 때 외부 I/O를 시작할 수 있다.

## WebFlux가 제공하지 않는 것

WebFlux는 inbound HTTP 요청 수, 전체 pipeline in-flight, DB/외부 서비스 예산, memory와 queue의 상한을 자동으로 정하지 않는다. non-blocking이라는 사실만으로 요청이 무한히 안전해지거나 overload가 자동으로 503이 되지는 않는다.

## Reactive Streams backpressure의 경계

Reactive Streams backpressure는 publisher/subscriber 사이의 demand 조절 계약이다. HTTP 요청이 이미 서버에 도착했거나 application이 pipeline을 구독한 뒤에는 이 계약만으로 전체 요청 admission을 거절하지 않는다. 따라서 HTTP body subscription 전에 명시적인 gate가 필요하다.

## Reactor Netty connection pool의 역할

Reactor Netty pool은 outbound channel acquire를 관리한다. `maxConnections`를 넘는 acquire는 pending이 되고, pending 상한과 acquire timeout에 따라 실패할 수 있다. 이는 outbound 자원 보호이지 전체 요청 path의 admission 또는 DB/CPU 예산을 의미하지 않는다.

## Overall concurrency limit

전체 request path를 하나의 `Mono.defer` 경계에서 계수하면 TOKEN→AI→STORAGE→DB가 차지하는 in-flight를 동일한 예산으로 볼 수 있다. ENFORCE에서는 limit을 넘은 요청의 action supplier를 호출하지 않아 body와 downstream I/O 구독을 시작하지 않는다.

## Dependency isolation

이번 실험은 SHARED pool을 고정한다. 따라서 dependency isolation을 새로 도입하거나 pool 예산을 바꾸지 않고, 먼저 전체 path admission이 기존 shared pool pressure를 보호하는지 확인한다.

## Queue와 fast-fail 비교

queue는 요청을 보존하지만 memory와 tail latency를 키울 수 있다. fast-fail은 overload 요청을 명시적인 503으로 돌려 accepted request의 latency와 goodput을 보호할 수 있다. 어느 쪽이 맞는지는 실제 capacity와 false-positive rejection을 함께 측정해야 한다.

## Retry 위험

overload 503을 자동 retry하면 거절된 요청이 다시 pool과 downstream을 압박해 overload를 증폭시킬 수 있다. 현재 request path에는 자동 retry가 확인되지 않았으므로 이번 실험에서 retry를 추가하지 않는다.

## 현재 DoEng 구현과의 일치점

현재 gate는 `Mono.defer`와 `doFinally`를 사용하고, WebClient/R2DBC는 reactive publisher를 반환한다. `/game/face`의 outer pipeline은 TOKEN→AI→STORAGE→DB를 한 요청으로 연결하고 있으며, SHARED provider를 고정할 수 있다.

## 현재 DoEng 구현의 부족한 점

기존 설정은 boolean `enabled`와 scope 문자열이 섞여 있어 OFF/OBSERVE/ENFORCE의 의미가 분리되지 않았다. 기존 metric도 전체 path started/completed/cancelled/would-reject를 표현하지 못했고, admission 503에 `Retry-After`가 없었다. permit 경계 밖의 request body decode와 scheduler queue는 직접 측정되지 않는다.

## 최종 적용 원칙

1. OFF는 기존 baseline 호환이며 pipeline에 계측을 추가하지 않는다.
2. OBSERVE는 limit을 넘겨도 실행하고 `would_reject`만 기록한다.
3. ENFORCE는 limit 초과 요청을 body/TOKEN/AI/STORAGE/DB 구독 전에 503 + `Retry-After: 1`로 거절한다.
4. 모든 terminal signal에서 release하고 permit leak은 0이어야 한다.
5. pool/timeout/workload를 바꾸지 않고 동일 binary의 mode/limit만 비교한다.
