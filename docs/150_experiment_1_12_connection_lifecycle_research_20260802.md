# Experiment 1-12 Connection Lifecycle Research

## 조사 목적

Experiment 1-11에서 확인한 AI `PrematureCloseException`을 request와 pooled channel, 양단 socket tuple, TCP FIN/RST에 연결하기 위한 현재 dependency와 실행 환경의 지원 범위를 확인한다. 성능 개선이나 pool 설정 변경은 범위가 아니다.

## 기준

- branch 기준: `experiment/doeng-ai-premature-close-correlation`
- result commit: `c845026209f7ec74c7a7217c36cf9d538ee1f3b2`
- Spring Boot 2.7.9
- Reactor Netty Core/HTTP 1.0.28
- Reactor Core 3.4.27
- Java 11

## Reactor Netty 1.0.28 확인 결과

로컬 Gradle cache의 `reactor-netty-core-1.0.28.jar`를 Java 11 `javap`으로 확인했다.

`ConnectionObserver.State`가 제공하는 상태:

- `CONNECTED`
- `CONFIGURED`
- `ACQUIRED`
- `RELEASED`
- `DISCONNECTING`

`reactor.netty.Connection`은 `channel()`을 제공한다. 실제 Netty channel에서 다음을 읽을 수 있다.

- `channel.id().asShortText()`
- `channel.id().asLongText()`
- `channel.localAddress()`
- `channel.remoteAddress()`

따라서 임의 channel ID를 만들지 않고 실제 channel identity를 사용할 수 있다. lease sequence와 request binding은 channel attribute에 진단 전용 값으로 기록한다. `ACQUIRED` 때 sequence를 증가시키고, 첫 lease는 `NEW_CHANNEL`, `RELEASED` 이후 다음 `ACQUIRED`는 `REUSED_CHANNEL`로 분류한다.

## 기존 구현과 최소 확장 지점

- `TransportHttpClientObservation`: 기존 request/response/connection callback을 유지하면서 channel state와 binding event를 추가한다.
- `TransportDiagnosticLogger`: request body나 인증정보 없이 structured connection event를 추가한다.
- `ExternalHttpClientConfig`: 선택된 `ConnectionProvider.name()`만 관측기에 전달한다. provider 설정은 변경하지 않는다.
- `backend/experiment-mock/server.js`: 기존 request lifecycle을 유지하고 server connection listener에서 socket tuple과 accepted/end/error/close를 기록한다.

nullable Reactor Netty error callback의 request 객체는 request identity로 사용하지 않는다. request identity는 기존 AI header와 `AI_REQUEST_CHANNEL_BOUND`의 channel/lease pair로만 연결한다.

## Packet capture 실행 가능성

Docker Desktop 환경에서 다음을 부하 없이 확인했다.

- sidecar image: `nicolaka/netshoot:v0.13`
- image digest: `sha256:a20c2531bf35436ed3766cd6cfe89d352b050ccc4d7005ce6400adf97503da1b`
- tcpdump 4.99.4 / libpcap 1.10.4
- `NET_RAW`, `NET_ADMIN` capability로 tcpdump 실행 성공

application과 mock image에는 tcpdump를 설치하지 않는다. 두 sidecar가 각각 `network_mode: service:flux-corrected`, `network_mode: service:experiment-mock`로 network namespace를 공유한다.

BPF는 mock port 9100의 SYN/FIN/RST만 허용한다.

```text
tcp port 9100 and (tcp[tcpflags] & (tcp-syn|tcp-fin|tcp-rst) != 0)
```

snap length는 96 bytes로 제한하고 pcap에는 control packet만 남긴다. HTTP header/body와 image payload는 filter 대상이 아니다.

## 확인된 제약

- connection-level callback에는 request ID가 없을 수 있다.
- request는 `channelId + leaseSequence`가 동일한 binding event가 있을 때만 connection error와 연결한다.
- mock connection event는 HTTP parsing 이전이므로 request ID를 가질 수 없다.
- application/mock connection은 정규화한 양방향 socket tuple로만 연결한다.
- packet 방향이 확인돼도 특정 request binding이 없으면 request 원인으로 승격하지 않는다.
- positive control이 tuple 및 FIN/RST 방향을 검증하지 못하면 core를 실행할 수 없다.

## 조사 판정

`IMPLEMENTATION FEASIBLE`

현재 dependency와 Docker 환경에서 명세의 channel lifecycle, request binding, mock socket lifecycle, 양단 control-packet capture를 최소 진단 확장으로 구현할 수 있다.
