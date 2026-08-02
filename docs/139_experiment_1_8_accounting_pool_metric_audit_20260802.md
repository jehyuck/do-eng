# Experiment 1-8 Accounting and Pool Metric Audit

## 확인한 자료

- 결과 문서: `docs/138_experiment_1_8_outbound_pool_isolation_result_20260802.md`
- ledger: `docs/11_run_ledger_exp18_addendum_20260802.md`
- pool source: `ExternalHttpClientConfig`, `ExternalServiceProperties`, `DiagnosticPoolEndpoint`
- collector: `experiment/scripts/collect-diagnostic-pool.ps1`
- summary: `experiment/scripts/summarize-pool-metrics.ps1`
- client accounting: `experiment/load/mission-load.js`
- VALID raw: SHARED replacement/003, ISOLATED 001/002/003

이번 작업에서는 source, raw, summary만 감사했고 부하·튜닝·설정 변경은 수행하지 않았다.

## RPS 계산식 감사

`experiment/load/mission-load.js`는 다음과 같이 기록한다.

```text
successfulRequests = HTTP 2xx 결과 수
failedRequests = results.length - successfulRequests
throughputRequestsPerSecond = results.length / (durationMs / 1000)
```

따라서 기존 문서의 약 196.9는 successful RPS가 아니라 전체 terminal 완료율(`completedRequests / 105초`)이다. 원본 raw의 `durationMs=105000`과 outcome count로 재계산한 값은 다음과 같다.

| Run | HTTP200 | 비성공 terminal | 측정초 | successful RPS | failed RPS | completed RPS | 기존 표기 |
|---|---:|---:|---:|---:|---:|---:|---:|
| SHARED-001-RPL-001 | 12,056 | 8,621 | 105 | 114.819 | 82.105 | 196.924 | 196.92 successful RPS |
| SHARED-003 | 12,291 | 8,396 | 105 | 117.057 | 79.962 | 197.019 | 197.02 successful RPS |
| ISOLATED-001 | 3,745 | 16,913 | 105 | 35.667 | 161.076 | 196.743 | 196.74 successful RPS |
| ISOLATED-002 | 9,606 | 11,058 | 105 | 91.486 | 105.314 | 196.800 | 196.80 successful RPS |
| ISOLATED-003 | 8,541 | 12,105 | 105 | 81.343 | 115.286 | 196.629 | 196.63 successful RPS |

`비성공 terminal`은 HTTP 500, timeout, connection error 등 HTTP 200이 아닌 완료 분류의 합이다. scheduled/started/completed accounting은 각 raw의 `completedClassifiedRequests == completedRequests`와 `finalUnfinishedRequests=0`으로 확인했다.

## 기존 표기 오류

`docs/138`의 `successful RPS` 열과 arm 중앙값은 completed RPS를 성공 처리율처럼 이름 붙인 표기 오류였다. raw와 validity는 변경하지 않고 결과 문서의 표기와 해석만 정정했다.

## 정정된 SHARED/ISOLATED 비교

VALID raw 기준 successful RPS는 다음과 같다.

- SHARED: 114.819, 117.057 → 중앙값 115.938 RPS
- ISOLATED: 35.667, 91.486, 81.343 → 중앙값 81.343 RPS
- ISOLATED/SHARED 중앙값 비율: 약 0.701
- completed RPS 중앙값은 각각 약 196.97, 196.74로 거의 같지만 이는 성공 처리율 비교가 아니다.

따라서 기존의 “successful RPS가 약 196.9”라는 해석은 폐기한다. 성공 처리율 기준으로는 ISOLATED가 증가하지 않았다.

## Pending metric 계산 경로

`DiagnosticPoolEndpoint`는 Micrometer Gauge를 다음 이름 그대로 노출한다.

```text
reactor.netty.connection.provider.pending.connections
reactor.netty.connection.provider.max.pending.connections
reactor.netty.connection.provider.active.connections
reactor.netty.connection.provider.max.connections
```

`collect-diagnostic-pool.ps1`는 endpoint 응답의 `name`, `value`, `tags`(name, remote.address, id), timestamp를 JSONL에 그대로 보존한다. `summarize-pool-metrics.ps1`는 현재 raw에서 provider별 각 metric의 관측 최대값과 동일 timestamp의 active/pending 합 최대를 계산한다.

ISOLATED-001/002를 raw key(`provider|remote.address|id|metric`)로 재확인한 결과:

- 각 provider마다 remote address 1개
- 각 provider마다 meter ID 1개
- `pending.connections`와 `max.pending.connections`는 별도 metric row
- provider 내부의 여러 timestamp를 합산하지 않음
- ISOLATED provider 간 동일 timestamp pending 합만 별도 계산

따라서 token pending 1,313/1,083은 `max.pending.connections=80`을 잘못 읽은 값이나 여러 meter 합산값이 아니다. 해당 시점의 단일 Gauge value 자체가 그렇게 기록되어 있다.

## Runtime pool 설정

`ExternalHttpClientConfig`는 `ConnectionProvider.builder(name)`에 `maxConnections`, `pendingAcquireMaxCount`, `pendingAcquireTimeout`을 전달한다. `ExternalServiceProperties.validatePoolContract()`는 ISOLATED의 설정 합이 SHARED 설정과 같은지 startup에서 확인한다.

| Mode | Provider | runtime max.connections | runtime max.pending.connections |
|---|---|---:|---:|
| SHARED | doeng-external | 400 | 800 |
| ISOLATED | doeng-token | 40 | 80 |
| ISOLATED | doeng-ai | 320 | 640 |
| ISOLATED | doeng-storage | 40 | 80 |

이 값은 모든 VALID raw의 actuator diagnostic metric row에서 확인됐다. 즉 설정 provenance와 runtime max Gauge는 일치한다.

## Provider·remote-address·pool ID 매핑

| Provider | Remote address in raw | meter id | max connections | max pending | current pending max |
|---|---|---|---:|---:|---:|
| doeng-external | `experiment-mock:9100` | run별 단일 ID | 400 | 800 | 1,292 / 1,679 |
| doeng-token | `experiment-mock:9100` | run별 단일 ID | 40 | 80 | 1,313 / 1,083 / 587 |
| doeng-ai | `experiment-mock:9100` | run별 단일 ID | 320 | 640 | 268 / 664 / 679 |
| doeng-storage | `experiment-mock:9100` | run별 단일 ID | 40 | 80 | 87 / 83 / 86 |

SHARED endpoint는 `doeng-external`만, ISOLATED endpoint는 세 dedicated provider만 노출한다. inactive provider meter가 최종 corrected raw에 섞이지 않은 것도 확인했다.

## 설정 상한과 관측값 충돌 원인

확정할 수 있는 사실은 다음까지다.

1. `max.pending.connections` Gauge는 설정값 80/640/800으로 정상 노출됐다.
2. `pending.connections` Gauge는 그 설정값을 넘어 1,313 등으로 관측됐다.
3. 해당 값은 한 provider·한 remote·한 meter ID의 raw Gauge다.
4. 현재 source와 raw만으로는 Reactor Netty 1.0.28 runtime에서 왜 pending Gauge가 configured max를 초과했는지 인과를 확정할 수 없다.

따라서 이를 summary의 오집계나 `max.pending` 혼동으로 정정할 수는 없다. 가능한 설명을 하나로 단정하지 않으며, `PoolAcquirePendingLimitException` 직접 count와 acquire wait의 원시 metric이 없어 상한 초과의 내부 원인은 **현재 확인 불가**로 남긴다.

## 현재 결과로 확인된 사실

- `196.9 RPS`는 successful RPS가 아니라 completed RPS다.
- 실제 successful RPS 중앙값은 SHARED 115.938, ISOLATED 81.343이다.
- corrected source에서 SHARED/ISOLATED provider wiring은 분리되어 있다.
- 모든 VALID run의 runtime max connection/max pending 설정은 계약과 일치한다.
- 현재 mock workload에서는 모든 provider의 remote address가 `experiment-mock:9100`이다.
- pending Gauge는 일부 run에서 configured max Gauge보다 크게 관측됐다.
- 최종 Experiment 1-8 분류 F와 raw 보존 규칙은 변경하지 않는다.

## 현재 결과로 확인되지 않은 사실

- pending Gauge 초과가 실제 pending acquire queue의 상한 위반인지, Reactor Netty 1.0.28 metric semantics/implementation 문제인지
- `PoolAcquirePendingLimitException`이 실제로 몇 번 발생했는지
- pending acquire wait의 p95/p99
- pending Gauge 초과가 HTTP 500의 직접 원인인지
- 실제 AI/S3 host에서도 동일한 remote/pool topology가 재현되는지

## 다음 isolation topology

실험 compose의 TOKEN, AI, STORAGE base URL은 모두 `http://experiment-mock:9100`으로 override되어 있다. 따라서 이번 결과는 **하나의 remote host에 대해 세 개의 logical ConnectionProvider를 분리한 3-way isolation**이다. production default source의 AI와 TOKEN도 같은 `j8a601.p.ssafy.io` host를 사용하고 storage는 별도 URL이지만, 이번 raw는 mock override 결과이므로 production topology로 일반화하지 않는다.

현재 자료만으로 다음 후보를 3-way에서 TOKEN/AI 2-way로 줄일 근거는 없다. 다음 isolation을 설계한다면 먼저 실제 dependency별 remote host와 provider별 acquire wait/exception을 계측해 3-way logical isolation과 2-way 후보의 차이를 사전등록해야 한다. 이번 작업에서는 새 실험을 시작하지 않는다.
