# Exp141 Pool Curve Reconstruction

## 질문

현재 동일 workload에서 Pool400과 Pool1000의 관측 곡선을 재구성할 수 있는가?

## 비교 기준

- 200 active missions
- 1초 interval/reconnect
- HIGH 30초, request timeout 10초
- AI 2,000ms, storage 100ms
- app 2 CPU / 3GiB, JVM Xms512m/Xmx2g
- SHARED provider `doeng-external`
- pending 800, Admission OFF, pool observation ON
- 결과는 단일 current run씩이며 통계적 유의성을 주장하지 않음

## Current controlled curve

| Cohort | Pool | Run | Successful RPS | Success rate | Failure rate | p95 | Peak active | Peak pending | Memory | Validity |
|---|---:|---|---:|---:|---:|---:|---:|---:|---|---|
| CURRENT_CONTROLLED_COHORT | 400 | `RUN-EXP139-POOL400-HIGH-001` | 86.03 | 43.28% | 56.72% | 9,409ms | 400 | 1,365 | 2.328GiB / 3GiB | VALID_CURRENT |
| CURRENT_CONTROLLED_COHORT | 1000 | `RUN-EXP140-POOL1000-HIGH-001` | 54.07 | 28.96% | 71.04% | 9,694ms | 1,000 | 905 | 2.434GiB / 3GiB | VALID_CURRENT |

### Raw outcome details

- Pool400: attempts 5,964; HTTP200 2,581; HTTP500 2,619; timeout 764; connection error 0; `PoolAcquirePendingLimitException` 4,868.
- Pool1000: attempts 5,600; HTTP200 1,622; HTTP500 939; timeout 2,949; connection error 90; `PoolAcquirePendingLimitException` 718.
- Pool400 peak application CPU/memory: 206.24% / 2.328GiB.
- Pool1000 peak application CPU/memory: 212.89% / 2.434GiB.
- 두 run 모두 accounting valid, drain completed, remaining AI/storage backlog 0, application/mock restart 0, OOMKilled false.

## Pool-specific labels

- Pool400: `SATURATED`. active가 400에 도달했고 pending과 pending-limit exception이 함께 관측됐다.
- Pool1000: `SATURATED`. active가 1000에 도달했고 pending과 pending-limit exception이 함께 관측됐다.
- `BEST_OBSERVED`: 현재 관측값만 비교하면 Pool400의 successful RPS와 success rate가 Pool1000보다 높다. 이는 production optimum이 아니며 단일 run의 관측 라벨이다.
- Pool500/600/700/750/800: `INSUFFICIENT_EVIDENCE` 또는 `NOT_COMPARABLE`; current controlled raw가 없다.

## Interpretation boundary

Pool1000은 active 상한을 열었지만 이 부하에서 상한에 다시 도달했다. 동시에 timeout과 connection error가 증가했으므로, pool 상한만으로 전체 성공률을 개선한다고 결론낼 수 없다. 현재 자료는 Pool400 또는 Pool1000이 전역 최적이라는 것을 증명하지 않는다.

Exp13의 세 VALID core는 Pool400에서 더 안정적인 역사적 맥락을 제공하지만 admission boundary가 달라 current cohort에 합산하지 않는다.
