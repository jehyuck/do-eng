# Experiment 1-15 — Lifecycle Timeline

작성일: 2026-08-03
원시 기준: `backend/doEngGameFlux/build/experiment-1-15/`

## cycle 구조

각 cycle은 동시에 하나의 request만 실행했다.

```text
A: request A ─ response/body complete ─ pool release
                 │
                 └── B: same channel reuse ─ response/body complete ─ pool release
                                                       │
                                                       └── mock FIN + server socket close
                                                                        │
                                                                        └── C: new channel acquire ─ request C
```

## 8-cycle 검증 결과

| Gate | 검증 방법 | 결과 | 의미 |
|---|---|---:|---|
| A — 정상 reuse | A/B의 final `REQUEST_SENT` channelId 비교 | 8 / 8 | close 전 pool reuse는 재현됨 |
| response/release 분리 | mock finish, response received, body completed, pool release event 비교 | 8 / 8 | release는 response/body completion과 별도 event |
| mock close | `MOCK_FIN_SENT`와 `MOCK_SOCKET_CLOSE_COMPLETED` | 8 / 8 | test-only peer close가 실제 close completion까지 실행됨 |
| B — passive close의 client 전달 | `CLIENT_CHANNEL_INACTIVE` | 0 / 8 | 현재 hook에는 직접 전달을 보지 못함 |
| B — 다음 요청의 channel | B/C의 final channelId 비교 | 8 / 8 새 channel | close된 B channel은 C의 최종 성공 channel이 아님 |
| C — mock duplicate | requestId별 handler count | 24 / 24가 1회 | 중복 mock arrival 없음 |

## 시간축에서 직접 확인된 것

```text
mock response finish
  → client response received          T1: 8/8
  → client response body completed    T2: 8/8
  → pool release observed             T3: 8/8
  → mock FIN scheduled                T4: 8/8, median 99ms
  → next C acquire                    T6: 8/8, median 12ms
```

`mock FIN → CLIENT_CHANNEL_INACTIVE`는 8회 모두 결측이다. 이 결측은 observer failure로 덮지 않고 결과로 보존한다.

## 해석 경계

- T1–T4와 T6은 localhost test-only environment의 event timestamp다. 운영 latency·throughput·capacity의 증거가 아니다.
- C가 새 channel을 사용한 사실은 client inactive callback이 언제 발생했는지, Reactor Netty가 어떤 내부 상태 전이를 거쳤는지, 누가 close를 initiator로 판단했는지를 증명하지 않는다.
- `REQUEST_PREPARED` state callback은 request send callback과 안정적인 인과 순서를 보장하지 않았다. 따라서 T7/T8은 수치화하지 않고 `NOT AVAILABLE`로 남겼다.
- 이 실험에는 failure/retry가 발생하지 않았다. retry 없음이라는 일반 결론이나 retry 원인 결론을 낼 수 없다.

## 결론

현재 timeline은 response finish–pool release–mock close–다음 신규 channel까지는 연결하지만, passive peer close의 client-side callback과 retry lifecycle을 연결하지 못한다. 최종 상태는 `INSUFFICIENT_LIFECYCLE_ATTRIBUTION`이다.
