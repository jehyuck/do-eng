# Exp153 Controlled A/B Completion Result

## 목적

동일한 60초·1 request/sec 이미지 요청에서 Cell A(기존 직접 reactive 경로)와 Cell B(Sink Dispatcher 경로)의 실행 가능성, tail latency, drain 상태를 비교했다. B1은 meter 부재 때문에 잘못 INVALID 처리된 기존 판정을 보정했으며, 부재를 숫자 0으로 대체하지 않았다.

## 고정 조건

- 동일 머신, `arc.jpg`, mock 지연, pool, admission, timeout, CPU·memory
- 60초, 1 request/sec, 동일 요청 계약
- A source `507e075016728daeaab75a51e7172577efe4c5ce`
- B source `cf5b36ad38928d55eab131d1328dc85ccff0ad3b`

## 유효 실행

| Cell | Run | 요청/완료/성공 | p50 | p95 | p99 | max | 판정 |
|---|---|---:|---:|---:|---:|---:|---|
| A | A1-RECOVERY-006 | 60/60/60 | 2146 ms | 2214 ms | 3042 ms | 3042 ms | VALID |
| A | A2-RECOVERY | 60/60/60 | 2144 ms | 2206 ms | 3016 ms | 3016 ms | VALID |
| A | A3-RECOVERY | 60/60/60 | 2145 ms | 2224 ms | 2979 ms | 2979 ms | VALID |
| B | B1-RECOVERY-001 | 60/60/60 | 2161 ms | 2530 ms | 4788 ms | 4788 ms | B1_VALID_WITH_METER_ABSENT |
| B | B2-RECOVERY | 60/60/60 | 2144 ms | 2205 ms | 3253 ms | 3253 ms | VALID |
| B | B3-RECOVERY | 60/60/60 | 2149 ms | 2192 ms | 2899 ms | 2899 ms | VALID |

모든 실행에서 HTTP 503, HTTP 504, client timeout, 기타 실패는 0건이었다. 달성 요청률과 성공 요청률은 각 run에서 1 request/sec이었다.

## B1 판정 보정

`B1-RECOVERY-001`은 load 60/60 성공, token·AI·storage queue/active 0/0, consumer termination 없음, `result_emission_failed` meter 부재 조건을 충족한다. 따라서 `B1_VALID_WITH_METER_ABSENT`로 재분류했다. `METER_ABSENT`를 측정값 0으로 취급하지 않았다.

## Cell A 중앙값

- success rate: 100% (60/60)
- p50: 2145 ms
- p95: 2214 ms
- p99: 3016 ms
- max: 3016 ms
- 503: 0
- 504: 0
- timeout: 0

## Cell B 중앙값

- success rate: 100% (60/60)
- p50: 2149 ms
- p95: 2205 ms
- p99: 3253 ms
- max: 3253 ms
- 503: 0
- 504: 0
- timeout: 0

## Cell B drain

- B1: token/AI/storage 0/0, consumer termination 없음, meter `METER_ABSENT`
- B2: token/AI/storage 0/0, consumer termination 없음, meter `METER_ABSENT`
- B3: token/AI/storage 0/0, consumer termination 없음, meter `METER_ABSENT`

## 비교와 한계

성공률과 처리율은 두 조건에서 동일했다. B의 p95 중앙값은 A보다 9 ms 낮지만, B1의 p99/max가 크게 높고 B run 간 tail 편차가 더 크다. 따라서 이 표본에서는 Sink Dispatcher의 일관된 성능 개선이나 안정성 개선을 확인할 수 없다. 통계적 유의성은 산출하지 않았다.

초기 A1-RECOVERY-003·004·005 등 실패 artifact는 보존했으며 최종 유효 세트에는 포함하지 않았다. `result_emission_failed` meter는 B 세 run 모두 부재하여 실제 0으로 해석할 수 없다.

## 최종 결정

`NO_CLEAR_BENEFIT`

현재 조건과 세 번의 유효 반복에서 Sink Dispatcher의 명확한 이점 또는 회귀를 입증할 수 없다.

## Claim boundary

주장 가능한 범위는 고정된 synthetic workload에서 두 경로의 실행 결과와 drain 상태를 비교했다는 사실까지다. 처리량 개선, 성공 RPS 증가, provider pending 감소, 최적 concurrency 도출 또는 일반적인 WebFlux 우수성은 주장하지 않는다.

`PRODUCTION JAVA CHANGE: NONE`

