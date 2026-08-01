# 최종 병목 판정

## 확인한 자료

- Source commit `b622e2b`
- Result commit `1bf7536`
- `RUN-20260801-EXP16-AI1000-001/002/003`
- `RUN-20260801-EXP16-AI500-001/002/003`
- 각 run의 `verification-summary.json`, `stage-observation.jsonl`,
  `pool-metrics.jsonl`, `container-stats.jsonl`, `database-metrics.jsonl`,
  `client-progress.jsonl`
- 현재 source의 `StageObservation`, `AiOutboundAdmissionGate`,
  `ExperimentSnapshotEndpoint`, `DiagnosticPoolEndpoint`

새 부하 실행·코드 수정·설정 변경은 수행하지 않았다.

## AI1000과 AI500 차이

| 지표 | AI1000 중앙값 | AI500 중앙값 | 방향 |
|---|---:|---:|---|
| Successful RPS | 136.3333 | 137.4762 | AI500 소폭 증가 |
| Controlled 503 | 30.186% | 29.862% | AI500 소폭 감소 |
| Accepted p95 | 4,089 ms | 4,503 ms | AI500 악화 |
| Accepted p99 | 7,959 ms | 8,308 ms | AI500 악화 |
| Timeout | 59 | 48 | AI500 소폭 감소 |
| Load-stop unfinished | 287 | 301 | AI500 소폭 증가 |
| Pool active max | 320 | 321 | 사실상 포화 수준 유지 |
| Pool pending max 중앙값 | 13 | 27 | AI500 증가 |

세 쌍 모두에서 AI500의 accepted p95는 AI1000보다 높았다. Pool pending도
세 쌍 모두 AI500이 높았다(26→66, 13→27, 10→18). 다만 pending acquire
시간 자체는 raw에 수집되지 않았다.

## 반복적으로 악화된 지표

각 stage의 누적 duration counter를 `durationMsTotal / started`로 계산한
run별 평균이다. p90은 세 run의 평균값에 대한 소표본 요약이며 request-level
tail 분포가 아니다.

| Stage 평균(ms) | AI1000 median / p90 / max | AI500 median / p90 / max | 반복성 |
|---|---:|---:|---|
| TOKEN | 272.3 / 287.2 / 290.9 | 429.2 / 438.4 / 440.7 | 3/3 AI500 악화 |
| AI | 1,366.7 / 1,383.1 / 1,387.2 | 1,045.1 / 1,054.0 / 1,056.2 | 3/3 AI500 개선 |
| STORAGE | 452.5 / 472.3 / 477.3 | 627.3 / 629.5 / 630.1 | 3/3 AI500 악화 |
| DB | 99.6 / 125.0 / 131.4 | 99.1 / 109.6 / 112.2 | 방향 불일치 |

TOKEN과 STORAGE 평균 duration은 AI500에서 세 run 모두 증가했지만,
각 stage의 maxInFlight는 오히려 낮거나 비슷했다. 따라서 이 두 평균만으로
단일 병목을 확정할 수 없다. AI stage 평균은 의도한 대로 낮아졌고, p95/p99
악화와 동시에 pool pending 및 TOKEN/STORAGE 평균이 증가했다.

Runtime 관측에서도 AI500의 application CPU 최대치는 약 212.2~216.2%,
memory 최대치는 약 76.6~77.9%, PIDs는 33~34였다. AI1000 대비 반복적인
새로운 메모리·PIDs 임계 초과는 확인되지 않았다. DB active/pending의
request-level tail 또는 event-loop pending task 시계열은 이 run artifact에
없다.

## 미측정 구간

다음은 현재 run에서 직접 측정되지 않았다.

- 전체 request duration의 permit 경계별 분해
- full-path permit holding duration
- Reactor Netty connection acquire wait duration
- request body decode duration
- Base64 decode duration
- scheduler queue wait duration
- response composition duration
- stage duration의 request-level p95/p99

Pool active/pending, stage 누적 평균, container CPU/memory는 있지만 위
구간을 대체할 수 있는 직접 측정값은 아니다.

## 최종 분류

**B — 병목 후보는 있으나 현재 계측으로 확정 불가**

AI500에서 pool pending, TOKEN 평균, STORAGE 평균이 반복적으로 증가하고
accepted p95/p99가 반복적으로 악화됐다. 그러나 TOKEN과 STORAGE 두 후보가
동시에 변했고, permit holding 및 connection acquire wait가 없어 어느
구간이 full-path permit을 실제로 점유했는지 분리할 수 없다. 따라서 A의
“실제 수정 가능한 병목 하나” 기준은 충족하지 않는다.

## 현재 Evidence로 확인된 병목

단일 병목으로 확정된 것은 없다.

현재 가장 강하게 관찰된 현상은 **AI500에서 outbound pool pending이
증가하고 TOKEN/STORAGE 평균 duration과 accepted tail latency가 함께
악화된 것**이다. 이는 pool·TOKEN·STORAGE 경계의 압력 후보이지, 특정
구현 결함의 확정 증거가 아니다.

## 수정 가능한 지점

현재는 수정하지 않는다. 원인이 분리되지 않았으므로 application source
optimization을 시작할 근거가 없다.

## 허용 가능한 다음 작업

필요할 경우 diagnostic pair 1회만 허용한다. 추가할 metric은 하나로
고정한다.

```text
full-path permit holding duration Timer
(p50 / p95 / p99, acquire 시점부터 terminal release까지)
```

AI1000과 AI500을 동일 조건으로 한 번씩만 비교해, AI500의 pool/stage
변화가 실제 permit 점유시간 증가로 이어졌는지 확인한다. 이 metric 없이
새로운 core 3회 반복이나 remediation을 시작하지 않는다.

## 금지할 다음 작업

- permit 값 변경 또는 sweep
- pool·timeout·VU·CPU·memory 변경
- 250ms 또는 다른 AI delay 실행
- MVC 비교
- 복수 remediation 제안
- application source 수정
- raw 삭제 또는 기존 Experiment 1-6 분류 변경

## 최종 목표와의 정렬

이번 질문의 답은 “AI500에서도 성공 RPS가 거의 늘지 않고 p95가 악화된
현상은 관찰되지만, 현재 Evidence만으로 수정 가능한 단일 병목을 특정할
수 없다”이다. 따라서 현재 단계에서는 **B**를 확정하고, 단 하나의
permit-holding metric을 추가하는 최소 diagnostic pair 외의 성능 튜닝은
중단한다.
