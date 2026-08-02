# Experiment 1-8 외부 outbound connection pool 분리 결과

## 1. 실험 질문과 고정 계약

같은 WebFlux VU200 workload와 같은 총 outbound budget(활성 400, pending 800)에서 TOKEN·AI·STORAGE를 하나의 Reactor Netty provider로 공유하는 경우와 provider를 분리하는 경우를 비교했다.

- WebFlux, VU 200, 105초, frame/reconnect 1초
- AI 2,000ms, storage 100ms, client timeout 10,000ms
- application 2 CPU / 3GiB, outbound active budget 400, DB pool 10
- 동일 fixture·payload·인증/토큰·mock·DB/storage contract, fresh JVM
- admission OFF, JFR OFF, application continuous snapshot OFF, mock continuous polling OFF
- DB/container/stage/pool observer ON, load-stop snapshot 및 30초 drain ON

SHARED는 `doeng-external=400/800`, ISOLATED는 `doeng-token=40/80`, `doeng-ai=320/640`, `doeng-storage=40/80`으로 고정했다. ISOLATED provider active 합과 pending 설정 합은 각각 400과 800이다.

## 2. 소스와 실행 provenance

- 기준 branch: `experiment/doeng-outbound-pool-isolation`
- corrected source commit: `fdc7e93acf166a9a79f651eab817220d26c18aa8`
- pool isolation implementation commit: `93001da`
- runner project correction commit: `811dfba`
- 결과 raw: `experiment/results/<RUN-ID>/`
- pool raw와 집계: 각 run의 `pool-metrics.jsonl`, `pool-summary.json`

첫 scout `SCOUT-001`은 compose project/port 충돌로 부하 전에 중단됐다. `SCOUT-002`는 wiring correction 이전 binary라 최종 gate에서 제외했고, corrected `SCOUT-003`은 provider와 budget 확인용으로 보존하되 aggregate에서 제외했다.

## 3. Run validity ledger

| Run | Arm | Measurement validity | 처리 |
|---|---|---|---|
| `RUN-20260802-EXP18-SHARED-001` | SHARED | INVALID | wiring correction 이전. raw 보존 |
| `RUN-20260802-EXP18-SHARED-001-RPL-001` | SHARED | VALID | 최종 후보 1 |
| `RUN-20260802-EXP18-ISOLATED-001` | ISOLATED | VALID | 최종 후보 1 |
| `RUN-20260802-EXP18-ISOLATED-002` | ISOLATED | VALID | 최종 후보 2 |
| `RUN-20260802-EXP18-SHARED-002` | SHARED | INVALID | stage observer timeout 1회 |
| `RUN-20260802-EXP18-SHARED-002-RPL-001` | SHARED | INVALID | load-stop/drain 초기 artifact와 reconnect artifact 누락 |
| `RUN-20260802-EXP18-SHARED-003` | SHARED | VALID | 최종 후보 2 |
| `RUN-20260802-EXP18-ISOLATED-003` | ISOLATED | VALID | 최종 후보 3 |

성능 저하·HTTP 500·backlog는 invalid 사유로 사용하지 않았다. INVALID는 observer 또는 lifecycle artifact가 계약을 검증하지 못한 경우에만 적용했다. SHARED arm은 replacement 한도를 사용한 뒤에도 VALID 3개를 확보하지 못했다.

## 4. VALID core system outcome

| Arm / Run | 성공 | 실패 | successful RPS | accepted p95/p99 (ms) | 동시 active max | pending max | drain time |
|---|---:|---:|---:|---:|---:|---:|---:|
| SHARED-001-RPL-001 | 12,056 | 8,621 | 196.92 | 8,703 / 9,529 | 400 | 1,292 | 5,015ms |
| SHARED-003 | 12,291 | 8,396 | 197.02 | 8,732 / 9,735 | 400 | 1,679 | 6,013ms |
| ISOLATED-001 | 3,745 | 16,913 | 196.74 | 8,538 / 9,301 | 400 | 1,313 | 3,001ms |
| ISOLATED-002 | 9,606 | 11,058 | 196.80 | 7,541 / 8,795 | 400 | 1,083 | 7,013ms |
| ISOLATED-003 | 8,541 | 12,105 | 196.63 | 8,414 / 9,357 | 400 | 782 | 7,003ms |

VALID run 기준 arm 관찰값은 다음과 같다.

- SHARED 성공 중앙값 12,056, successful RPS 중앙값 196.97, accepted p95 중앙값 8,718ms, pending max 중앙값 1,486
- ISOLATED 성공 중앙값 8,541, successful RPS 중앙값 196.74, accepted p95 중앙값 8,414ms, pending max 중앙값 1,083
- ISOLATED의 세 run 모두 HTTP 500과 client failure가 남았고, successful RPS는 SHARED보다 증가하지 않았다.
- 모든 VALID run은 최종 unfinished 0, drain completed true였다.

## 5. Provider metric 관찰

SHARED에서는 endpoint와 raw 모두 `doeng-external`만 활성 provider로 기록됐다. ISOLATED에서는 `doeng-token`, `doeng-ai`, `doeng-storage`만 기록됐다. 동일 timestamp active 합의 최대는 모든 VALID run에서 400 이하였다.

다만 pending metric은 설정된 pendingAcquireMaxCount의 합과 다르게 관측됐다. 예를 들어 ISOLATED-001은 token pending 1,313, ISOLATED-002는 token pending 1,083까지 나타났다. 이는 실행 중 system outcome으로 보존했으며, collector가 추정값으로 보정하지 않았다. `PoolAcquirePendingLimitException`과 `PrematureCloseException` 개수는 현재 collector에 직접 노출되지 않아 `NOT_AVAILABLE`이다.

## 6. Stage 관찰

stage counter의 첫/마지막 관측값으로 계산한 interval mean은 다음과 같다. 이는 전체 request latency가 아니라 관측된 stage counter 구간 평균이다.

| Run | TOKEN mean | AI mean | STORAGE mean | DB mean | 비고 |
|---|---:|---:|---:|---:|---|
| SHARED-001-RPL-001 | 1,778ms | 3,495ms | 1,725ms | 78ms | stage maxInFlight도 raw 보존 |
| SHARED-003 | 1,926ms | 3,483ms | 1,745ms | 41ms | stage observer 0 failure |
| ISOLATED-001 | 2,236ms | 3,474ms | 850ms | 75ms | token pending 및 실패 집중 |
| ISOLATED-002 | 1,118ms | 4,762ms | 496ms | 33ms | AI tail 및 token pending 관찰 |
| ISOLATED-003 | 643ms | 4,822ms | 658ms | 23ms | provider pending 합 782 |

Stage counter에는 stage별 maxInFlight가 포함되지만, connection acquire 대기시간 자체와 `PoolAcquirePendingLimitException` count는 직접 측정되지 않았다.

## 7. 최종 분류

**F — INVALID / VALID cohort 미완성**

설계서의 최종 판정 A/B/C는 각 arm의 VALID core 3개를 전제로 한다. 현재 SHARED는 VALID 2개뿐이고, `SHARED-002`와 그 replacement는 각각 observer/lifecycle 계약 실패로 제외됐다. 따라서 이 결과만으로 A·B·C 중 하나를 최종 확정하지 않는다.

단, 확보된 VALID raw의 방향성은 C(`POOL ISOLATION NOT EFFECTIVE`)에 가깝다. ISOLATED에서 HTTP 500·client failure가 제거되지 않았고 successful RPS가 증가하지 않았으며, 일부 provider의 pending이 계속 크게 관찰됐다. 그러나 이는 불완전한 cohort에서의 관찰이며 최종 claim으로 승격하지 않는다.

## 8. 현재 증거가 말하는 범위

- provider wiring 분리는 corrected binary에서 실제로 동작했다.
- active connection 총예산 400은 두 topology에서 관측상 유지됐다.
- 이 workload와 자원 조건에서 분리만으로 HTTP 500, connection/pending 압력, tail latency를 안정적으로 제거했다는 증거는 없다.
- `PoolAcquirePendingLimitException`의 직접 발생 횟수와 connection acquire wait time은 측정되지 않았다.
- WebFlux 일반 우위, 모든 pool allocation의 최적성, 실제 AI/S3 환경의 일반화는 증명하지 않는다.

## 9. Hard stop

이번 실행에서 허용된 corrected core와 arm replacement를 모두 소진했다. 추가 tuning, budget 재배분, pending sweep, timeout/VU/AI delay 변경, admission 재활성화, MVC 비교는 자동으로 시작하지 않는다. 다음 작업은 이 결과와 raw를 근거로 Evidence/Claim 범위를 검수하는 단계로 제한한다.
