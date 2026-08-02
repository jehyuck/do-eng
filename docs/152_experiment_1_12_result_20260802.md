# Experiment 1-12 결과 — Pooled Connection Reuse와 TCP 종료 주체

## Validity

- Core: `RUN-20260802-EXP112-CLEAN-001`
- 실행 횟수: 사전등록대로 CLEAN core 1회
- 기존 실행 계약 판정: `VALID`
- Experiment 1-12 귀속 완전성: `VALID BUT ATTRIBUTION INCOMPLETE`
- 최종 분류: `G — PARTIALLY_ATTRIBUTED`
- source commit: `9e8ec269df80f54b34595da0b858f00cabc6e574`
- app image: `sha256:f2fd19b20cffc57f77159e1b1e45b7d8713ccb19f9143b75e7ff32f503e09976`
- capture image: `nicolaka/netshoot:v0.13` / `sha256:a20c2531bf35436ed3766cd6cfe89d352b050ccc4d7005ce6400adf97503da1b`

`verification-summary.json`의 모든 필수 assertion이 참이다. 200명 로그인, corrected accounting, DB progress/picture 각 1건, storage object 각 1건, fixture 일치, container/DB monitor, load-stop/drain artifact가 확인됐다. load-stop 시 AI/storage in-flight는 149/17이었고 7,008ms에 0이 됐으며 30초 drain은 완료됐다.

core 종료 뒤 runner가 전용 capture artifact 복사·집계를 완료하지 못했다. 이미 종료된 capture sidecar의 pcap과 원본 application log는 온전히 남아 있었으므로 core를 재실행하지 않고 후처리만 복구했다. 이 복구는 workload, runtime 또는 측정 결과를 변경하지 않았다.

## Positive control

최종 양성 대조 artifact: `experiment/results/CONTROL-20260802-EXP112-POSITIVE-001/`

다음 assertion이 모두 통과했다.

- 최초 연결을 `NEW_CHANNEL`로 분류
- release 후 재획득 연결을 `REUSED_CHANNEL`로 분류
- AI request ID를 실제 Netty channel ID와 leaseSequence에 결합
- 재사용 채널의 정상 요청이 HTTP 200으로 완료
- mock 강제 종료에서 mock FIN이 먼저이고 application PrematureClose와 tuple join 성공
- client cancellation에서 application FIN이 먼저이고 mock incomplete/close와 tuple join 성공
- diagnostic OFF 테스트에서 기존 client 객체와 semantics 유지
- admission 503 요청에 AI channel binding 없음

사전 실행 중 포트 점유와 pcap 디코더 stderr 처리 오류가 각각 발견됐지만 두 경우 모두 CLEAN core 전의 setup/diagnostic 문제였다. 첫 유효 대조에서는 임의의 5ms race 규칙이 정상 FIN 응답까지 `BOTH_OR_RACE`로 오분류함을 확인했다. 명세의 “첫 FIN/RST source”에 맞춰 동일 capture timestamp일 때만 race로 판정한 뒤 최종 대조가 통과했다.

## Core result

주요 system outcome은 다음과 같다.

| 항목 | 값 |
|---|---:|
| started/completed classified requests | 19,895 / 19,895 |
| HTTP 200 | 3,115 |
| HTTP 500 | 234 |
| controlled 503 | 4,530 |
| TypeError | 9,621 |
| AbortError | 2,395 |
| accepted p95 / p99 | 9,123ms / 9,879ms |
| final unfinished requests | 0 |
| AI PrematureClose requests | 108 |

Experiment 1-11 방식의 request-level correlation에서도 AI PrematureClose 108건은 모두 AI stage failure와 HTTP 500으로 이어졌고, 대응 mock HTTP request receive는 확인되지 않았다.

## New vs reused connection

두 층위를 분리해야 한다.

1. request-level: 108개 실패 요청 모두 `AI_REQUEST_CHANNEL_BOUND`가 없어 NEW/REUSED를 개별 요청에 확정할 수 없다.
2. connection-level: AI `PREMATURE_CLOSE` connection event는 정확히 108건이며 모두 서로 다른 `REUSED_CHANNEL` lease다. NEW_CHANNEL event는 0건이다.

108개 connection event 모두 이전 `RELEASED`, 현재 `ACQUIRED`, `REQUEST_PREPARED`가 있었고 현재 lease의 `REQUEST_SENT`는 0건이었다. 따라서 재사용된 연결을 획득하고 요청을 준비하는 사이 또는 직후에 전송 전 실패한 connection-level 패턴은 반복 확인됐다.

그러나 명세는 request ID가 없는 connection event를 임의의 요청에 배정하지 못하게 한다. 두 집합의 건수가 모두 108이라는 이유만으로 개별 request-to-channel 관계를 만들어내지 않았다. 따라서 `FAILURE_ON_REUSED_CHANNEL_CONFIRMED`를 request-level 최종 판정으로 쓰지 않는다.

## Application/mock socket tuple join

- 전체 request row: 19,895
- `COMPLETE`: 1,149
- incomplete: 18,746
  - `MISSING_REQUEST_BINDING`: 14,877
  - `MISSING_PACKET`: 3,540
  - `AMBIGUOUS_TUPLE`: 329
- AI PrematureClose 108건의 request-level completeness: 모두 `MISSING_REQUEST_BINDING`
- 캡처되어 정규화된 SYN/FIN/RST packet: 11,392

정상·취소 요청 일부에서는 request → application channel/lease → socket tuple → mock connection → packet 연결이 완성됐다. 실패 요청에서는 outbound write 완료 전 오류 때문에 binding event가 생성되지 않아 동일 join을 완성하지 못했다.

## FIN/RST direction

request ID를 추론하지 않는 connection-level 분석 결과는 다음과 같다.

| AI PREMATURE_CLOSE connection event | 값 |
|---|---:|
| 전체 | 108 |
| first close actor = mock | 108 |
| first close actor = application | 0 |
| mock close가 ACQUIRED보다 먼저 | 107 |
| mock close가 ACQUIRED 이후 | 1 |
| control packet 없음 | 0 |

모든 event에서 같은 application/mock tuple의 최초 FIN/RST source는 mock이었다. 107건은 mock 종료가 해당 lease의 재획득보다 먼저 관측됐고, 1건은 재획득 직후부터 PrematureClose 전 사이에 관측됐다. 이는 이미 mock이 종료한 pooled channel을 다시 획득하는 transport 패턴을 강하게 지지한다.

단, 이 표는 connection-level 결과다. request binding이 없는 상태에서 개별 108개 실패 요청에 channel을 배정하지 않았으므로 `MOCK_SIDE_CLOSE_CONFIRMED` 역시 request-level 확정이 아니라 connection-level evidence로 한정한다.

## AI PrematureClose request 결과

- request-level AI PrematureClose: 108
- HTTP 500과 연결: 108
- mock HTTP request received: 0
- request-bound NEW_CHANNEL 실패: 0 (확인 불가)
- request-bound REUSED_CHANNEL 실패: 0 (확인 불가)
- corresponding unbound connection-level PREMATURE_CLOSE: 108, 모두 REUSED_CHANNEL

직접 관측된 순서는 `prior RELEASED → mock FIN/RST → ACQUIRED(대부분) → REQUEST_PREPARED → PREMATURE_CLOSE`다. 다만 request ID가 `REQUEST_PREPARED` 시점에 channel event에 실리지 않았기 때문에 개별 request causality는 완성되지 않았다.

## Client cancellation 결과

- client deadline/AbortError: 2,395
- application 최초 close + mock request 수신 + tuple join이 모두 확인된 cancellation chain: 934

양성 대조와 core 모두 application/client cancellation이 application 쪽 FIN으로 시작되어 mock incomplete/close로 이어지는 별도 chain이 존재함을 확인했다. 이는 108개의 AI PrematureClose 집합과 분리해 유지한다.

## 최종 판정

`G — PARTIALLY_ATTRIBUTED`

확인된 사실:

- CLEAN core에서 AI PrematureClose 108건이 재현됐다.
- 같은 시간대의 connection-level PREMATURE_CLOSE 108건은 모두 재사용 lease였다.
- 108건 모두 같은 tuple에서 mock이 최초 종료 패킷을 보냈다.
- 107건은 mock 종료 뒤 해당 channel이 다시 ACQUIRED됐다.
- 실패 connection lease는 REQUEST_PREPARED까지 갔지만 REQUEST_SENT는 없었다.

확정하지 않는 사실:

- 특정 실패 request ID가 특정 channel/lease에서 실행됐다는 개별 매핑
- 108개 request 각각에 대한 `FAILURE_ON_REUSED_CHANNEL_CONFIRMED`
- 단일 설정값이나 remediation이 원인을 제거한다는 주장

따라서 stale pooled connection 재사용 메커니즘은 connection-level에서 강하게 지지되지만, 사전등록된 엄격한 request/channel join 조건을 충족하지 못해 완전한 인과 귀속으로 승격하지 않는다.

## 수정 가능한 대안

이번 작업에서는 구현하거나 시험하지 않았다. 후속 실험을 별도로 사전등록한다면 후보는 다음 범위다.

- maxIdleTime / maxLifeTime
- background eviction
- pool leasing 또는 freshness 정책

현재 결과만으로 어느 하나를 최적 remediation으로 선택할 수 없다.

## 아직 확인하지 못한 내용

- outbound write 이전에도 request ID를 channel lease에 결합할 수 있는 관찰 지점
- 개별 실패 request와 108개 reused connection event의 1:1 관계
- freshness/eviction 설정 하나가 해당 패턴을 제거하는지
- 로컬 Docker 외 환경에서 같은 close-before-acquire 패턴이 반복되는지

## Experiment 1-9~1-11 claim 영향

- Experiment 1-11의 “AI PrematureClose가 mock HTTP handler 도달 전에 발생한다”는 관찰을 유지하고, 그 이전 transport 구간에서 mock이 종료한 pooled connection의 재획득 패턴을 추가했다.
- admission/overload control로 받아들인 요청 수를 제한하는 Experiment 1-9 계열의 결론과 충돌하지 않는다. 이번 결과는 accepted request 내부의 별도 transport failure mechanism을 다룬다.
- WebFlux 또는 Reactor Netty 일반의 결함으로 확대하지 않는다. 현재 source, pool contract, mock keep-alive 동작과 로컬 Docker 환경에서 얻은 connection-level evidence다.

원시/파생 artifact:

- `experiment/results/RUN-20260802-EXP112-CLEAN-001/connection-correlation.jsonl`
- `experiment/results/RUN-20260802-EXP112-CLEAN-001/connection-correlation-summary.json`
- `experiment/results/RUN-20260802-EXP112-CLEAN-001/connection-mechanism-details.jsonl`
- `experiment/results/RUN-20260802-EXP112-CLEAN-001/connection-mechanism-summary.json`
- `experiment/results/RUN-20260802-EXP112-CLEAN-001/capture/`
- `experiment/results/RUN-20260802-EXP112-CLEAN-001/connection-provenance.json`
