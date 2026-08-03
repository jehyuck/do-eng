# Experiment 1-16 — Close/Acquire Race Timeline

작성일: 2026-08-03
원시 기준: `backend/doEngGameFlux/build/experiment-1-16/`

## 고정 cycle

```text
A request → release
  ↓ same client channel
B request → release
  ↓ 100ms 뒤
MOCK_CLOSE_INITIATED
  ├─ C_RACE_START_SIGNAL_RECEIVED
  ├─ C LOGICAL_REQUEST_CREATED       (close future completion을 기다리지 않음)
  └─ server channel.close()
       ↓
MOCK_CLOSE_FUTURE_COMPLETED
       ↓
CLIENT_CLOSE_FUTURE_COMPLETED
       ↓
C POOL_CONNECTION_ACQUIRED (new channel)
       ↓
C REQUEST_SENT → mock handler 1회 → success
```

## 8회 결과

| 관측 | 결과 |
|---|---:|
| A/B 정상 pooled reuse | 8 / 8 |
| C logical request가 mock close completion 이전 생성 | 8 / 8 |
| B old channel의 client closeFuture completion | 8 / 8 |
| C의 old channel acquire | 0 / 8 |
| C의 new channel acquire 및 final success | 8 / 8 |
| C의 pre-send failure | 0 / 8 |
| C의 internal retry 추론 | 0 / 8 |
| mock handler duplicate | 0 |

## 해석

이번 timing에서는 C 요청이 close completion 이전에 생성됐지만 acquire 직전에는 old client channel의 closeFuture가 완료됐다. 그래서 C의 final acquire는 old channel을 선택하지 않았고 retry가 발생하지 않았다.

이는 `POOL_FILTERED_CLOSED_CHANNEL`의 직접 event 조합이다. 단, TCP FIN/RST packet flag와 Reactor Netty 내부 retry decision hook은 수집하지 않았으므로, TCP close 종류나 retry engine 내부 이유까지 단정하지 않는다.

## 경계

- timestamp 근접성만으로 request를 결합하지 않았다. requestId와 strict single-flight test isolation을 함께 사용했다.
- C가 실제 old channel을 acquire하도록 timing을 추가 조정하지 않았다. 결과를 본 뒤 close delay·cycle 수·acquire delay를 바꾸지 않았다.
- production lifecycle 설정과 부하 조건은 변경하지 않았다.

## 결론

Experiment 1-16은 close/acquire race의 관측 경로를 완성했다. 이 고정 경계에서 pool은 close 완료된 old channel을 C에 제공하지 않았고, retry/duplicate mock handler 없이 신규 channel으로 성공했다.
