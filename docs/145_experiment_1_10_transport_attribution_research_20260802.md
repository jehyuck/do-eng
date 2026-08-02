# Experiment 1-10 Transport Failure Attribution — 사전 조사

## 범위

Experiment 1-9 ENFORCE-001에서만 관찰된 client connection error, timeout, HTTP 500의 경계를 구분하기 위한 관측 설계다. 성능 개선, admission/pool 조정, workload 변경은 범위에 포함하지 않는다.

## 확인하려는 경계

1. 부하 생성기와 WebFlux 사이의 연결·응답 전달 실패
2. WebFlux inbound/event-loop 단계의 취소 또는 미커밋 종료
3. TOKEN/AI/STORAGE WebClient outbound 단계의 pool·connect·response 실패
4. 애플리케이션 응답 커밋 이후 client response-body 전달 실패
5. 이전 실행의 dependency/runtime 상태 잔류

## 현재 증거의 공백

- 기존 client 결과는 `TypeError`/`AbortError` 수준으로 저장되어 원인 체인이 없다.
- inbound request ID와 outbound stage callback을 동일 시간축으로 연결하지 않는다.
- 응답 헤더 수신과 body 읽기 실패가 하나의 `fetch` 구간으로 합쳐져 있다.
- 기존 pool 관측은 상태 snapshot 중심이며, 특정 실패의 request ID·stage와 직접 연결되지 않는다.

## 관측 원칙

- 기존 reactive chain의 반환·예외 전파·status mapping을 유지한다.
- 모든 상세 관측은 diagnostic flag가 켜진 실행에서만 활성화한다.
- request ID는 JSONL/log correlation에만 사용하고 metric tag로 사용하지 않는다.
- request body, image, authorization token은 기록하지 않는다.
- 원인을 찾지 못하면 `UNRESOLVED`로 남기며 단일 지표로 추정하지 않는다.

## 분류 taxonomy

| 경계 | 판정에 필요한 직접 증거 |
|---|---|
| LOAD DRIVER/INBOUND TRANSPORT | Node 원인 chain의 ECONN*, Undici socket/headers 오류와 WebFlux 미수신 상관 |
| WEBFLUX INBOUND/EVENT LOOP | WebFlux request ID 수신, response 미커밋, outbound 미시작, event-loop 상태 |
| WEBCLIENT OUTBOUND | 고정 stage callback의 pool/connect/response 오류와 request ID 일치 |
| RESPONSE DELIVERY | 앱 response committed 이후 Node body/socket 오류 |
| RUNNER STATE CONTAMINATION | dependency clean/reused sequence 간 반복 차이 |
| UNRESOLVED | 재현·상관·경계 증거가 불완전하거나 여러 경계가 동시에 가능 |

## 실행 전 확인

Reactor Netty API와 현재 Gradle dependency를 local build에서 확인한다. 최신 문서의 metric 이름을 소급하지 않고 실제 runtime에서 노출되는 값만 기록한다.

## 사전 결론

현재 자료만으로 ENFORCE-001 원인을 확정하지 않는다. Experiment 1-10은 동일 조건의 clean dependency 3회와 reused dependency 3회를 비교해 경계 귀속 가능성만 검증한다.
