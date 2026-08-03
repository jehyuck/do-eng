# Experiment 1-16 — Close/Acquire Race Attribution Plan

작성일: 2026-08-03

## 질문

peer close initiation과 다음 pooled acquire를 같은 경계에서 겹치게 했을 때, C 요청이 old channel을 선택했는지, pre-send failure/retry가 있었는지, 최종 channel과 mock handler 도달 횟수까지 한 cycle로 귀속할 수 있는가?

## 선행 상태

- Experiment 1-15는 close completion 뒤 C를 시작해 정상 reuse·신규 channel은 확인했지만, idle client channel의 `channelInactive`를 0/8 관측했다.
- 현재 lifecycle remediation 근거는 충분하지 않으며, 이 단계는 test-only 관측 보강 1회다.

## 고정 조건

- Reactor Netty 1.0.28 / Java 11 / localhost test-only server
- test-local `ConnectionProvider`의 `maxConnections=1`, strict single-flight, 8 cycle
- FIFO default와 production lifecycle/pool/timeout/retry/admission 설정을 변경하지 않음
- load/VU/MVC 실행 및 lifecycle remediation 금지

## Deterministic race

각 cycle은 A 정상 요청·release, B 정상 reuse·release 뒤 다음 순서로 진행한다.

1. B response 완료 뒤 server가 100ms close timer를 등록한다.
2. timer가 실행되면 server는 `MOCK_CLOSE_INITIATED`를 기록한다.
3. **동일 server event-loop callback에서** C 시작 barrier를 해제하고 `channel.close()`를 호출한다.
4. test thread는 barrier를 받은 즉시 C를 시작한다. mock/client close future completion은 기다리지 않는다.
5. C의 acquire, prepared/send, failure/success, 최종 channel과 mock handler 도달을 기록한다.

이 순서와 100ms delay, 8회 반복 수는 결과에 따라 바꾸지 않는다.

## Client close observation

`HttpClient.doOnChannelInit`에서 channel마다 한 번만 다음을 등록한다.

- `CLIENT_CLOSE_LISTENER_REGISTERED`
- `channel.closeFuture().addListener(...)` → `CLIENT_CLOSE_FUTURE_COMPLETED`
- `ChannelInboundHandlerAdapter` → `CLIENT_CHANNEL_INACTIVE`, `CLIENT_CHANNEL_UNREGISTERED`

listener를 요청 hook에 등록하지 않는다. `closeFuture` event에는 마지막 channel binding을 사용하되, C acquire와 race인 경우 event 자체의 channelId/leaseId를 우선 근거로 남긴다.

## Attribution 및 분류

requestId/attemptId는 logical request 기준으로 기록한다. acquire 직전 public hook에 request가 직접 전달되지 않는 제약은 유지하므로, strict single-flight에 한해 `DETERMINISTIC_SINGLE_FLIGHT_ATTRIBUTION_USED`를 명시한다.

각 cycle은 다음 중 하나만 분류한다.

- `POOL_FILTERED_CLOSED_CHANNEL`
- `OLD_CHANNEL_ACQUIRED_THEN_RETRIED`
- `OLD_CHANNEL_ACQUIRED_AND_FAILED`
- `POST_SEND_CLOSE`
- `NOT_ATTRIBUTABLE`

retry는 direct public hook이 없으므로, 명세의 old acquire → pre-send failure/close → second acquire → one final send/mock handler → success 조건을 모두 만족할 때만 `STRONGLY_INFERRED`로 표기한다.

## 성공·실패 기준

성공 기준은 client closeFuture 8/8, mock close initiation과 C acquire의 순서 8/8, old/new acquire 판정, logical request와 후속 acquire 결합, send/mock handler 수 확인, production lifecycle 무변경이다.

필수 event가 결측이거나 C가 close completion 뒤에만 시작되면 `INSUFFICIENT_CLOSE_ACQUIRE_ATTRIBUTION`으로 판정한다. 결과가 어떠하든 remediation이나 다음 실험은 자동 시작하지 않는다.

## 산출물

`backend/doEngGameFlux/build/experiment-1-16/`에 JSONL, cycles JSON, summary JSON, timeline CSV, validity JSON을 생성한다. build artifact는 Git에 stage하지 않는다.
