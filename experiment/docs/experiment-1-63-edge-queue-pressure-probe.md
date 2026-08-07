# Exp163 Repaired Sink Edge Queue Pressure Probe

## 실행 기준

- START_HEAD: `188b0d32308771596993c893e4369871dc84d806`
- source provenance gate: PASS
- serialization unit test: PASS
- valid run: `SINK-C400-Q6-EDGE-R1`
- Exp162와 동일한 workload/provider/concurrency이며 TOKEN/STORAGE queue만 300→600으로 변경
- AI queue는 1200으로 유지
- production Java 변경 없음

## 변경 조건

| 항목 | Exp162 Q3 | Exp163 Q6-edge |
|---|---:|---:|
| TOKEN queue | 300 | 600 |
| AI queue | 1200 | 1200 |
| STORAGE queue | 300 | 600 |
| TOKEN/AI/STORAGE concurrency | 100/400/100 | 100/400/100 |
| provider max/pending | 100/160, 600/960, 100/160 | 동일 |

## Primary outcome

| 지표 | Exp162 Q3 | Exp163 Q6-edge |
|---|---:|---:|
| attempted requests | 5,908 | 5,964 |
| HTTP 200 | 2,380 | 2,682 |
| accepted HTTP200/sec | 79.33 | 89.40 |
| accepted success rate | 40.28% | 44.97% |
| accepted HTTP200 p95 | 12,545ms | 11,068ms |
| overall p95 | 12,634ms | 12,812ms |
| HTTP 500 | 198 | 71 |
| HTTP 503 downstream | 2,180 | 740 |
| HTTP 504 | 1,016 | 2,470 |
| client deadline | 134 | 1 |
| CONNECT_REFUSED | 0 | 0 |
| max in-flight | 2,168 | 2,094 |

## EmitResult 및 queue 관측

```text
FAIL_NON_SERIALIZED = 0
```

Exp163의 `FAIL_OVERFLOW`는 740건이며 TOKEN 680, AI 60, STORAGE 0이다. Q3의 2,180건(TOKEN 1,869, STORAGE 311)보다 줄었지만, 감소한 rejection이 HTTP 504로 이동했다.

| dispatcher | configured queue | sampled peak | final queue | active peak | queue wait |
|---|---:|---:|---:|---:|---|
| TOKEN | 600 | 600 | 0 | 100 | `NOT_AVAILABLE` |
| AI | 1200 | 1200 | 0 | 400 | `NOT_AVAILABLE` |
| STORAGE | 600 | 391 | 0 | 100 | `NOT_AVAILABLE` |

1초 polling에서 TOKEN과 AI queue가 상한까지 관찰됐다. queue wait의 count/total/max/percentile은 endpoint에서 제공되지 않아 `NOT_AVAILABLE`로 기록한다.

## Backlog 및 자원

- load-stop AI in-flight: 325
- load-stop Storage in-flight: 1
- drain completed: true
- time-to-zero: 10,016ms
- OOM: 없음
- application restart: 없음
- application CPU 평균: 62.91%
- application CPU peak: 204.12%
- application memory peak: 2.323GiB / 3GiB
- dispatcher consumer termination: 확인되지 않음
- provider timeline: `NOT_AVAILABLE`

## 최종 판정

```text
BACKLOG_RELOCATION: SUPPORTED
EDGE_QUEUE_CAPACITY_SIGNAL: NOT_SUPPORTED
```

queue capacity를 늘리자 overflow는 2,180→740으로 감소하고 accepted HTTP200/sec는 79.33→89.40으로 증가했다. 그러나 HTTP504는 1,016→2,470으로 증가했고 overall p95도 12,634→12,812ms로 개선되지 않았다. 따라서 queue 확대가 순수한 성능 개선이라기보다 일부 즉시 rejection을 더 긴 deadline backlog로 이동시킨 결과로 판정한다.

## 다음 단계

```text
NEXT_EXPERIMENT_CLASS: EDGE CONCURRENCY / SERVICE CAPACITY REVIEW
NEXT_RECOMMENDED_STEP: queue 추가 확대를 자동 진행하지 말고, TOKEN/STORAGE downstream 처리 용량과 deadline backlog의 관계를 별도 설계
```

이번 작업에서는 queue 900/1200/1800, concurrency, provider pool, dynamic controller를 실행하지 않았다.

