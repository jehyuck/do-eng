# Exp165 — Finite-Batch Long-Deadline Stage Residency Diagnostic

## 목적

이 실행은 성능 winner를 정하거나 HTTP 200/s를 주장하기 위한 실험이 아니다. 고정된 300개 유한 배치에서 요청이 TOKEN·AI·STORAGE·DB stage에 실제로 머문 시간과 drain 순서를 관찰하는 진단이다.

## 기준과 변경

- branch: `experiment/exp152-sink-dispatcher`
- source/harness commit: `2a0f35e2ee9e22330e315154e6f270db0dcbfad9`
- 기존 Exp162 repaired C400/Q3 설정 재사용
- provider: TOKEN 100/160, AI 600/960, STORAGE 100/160
- logical concurrency: TOKEN 100, AI 400, STORAGE 100
- queue: TOKEN 300, AI 1200, STORAGE 300
- Admission OFF, FIFO, serialization repair 유지
- AI/storage mock: 2000ms / 100ms, HTTP 200
- application 2 CPU / 3 GiB, JVM `-Xms512m -Xmx2g -XX:+UseG1GC`, DB pool 10
- batch 300개, 1개씩만 전송, reconnect 없음, 1초 구간에 staggered arrival
- diagnostic client/application deadline: 60초
- drain observation: 60초

Production Java는 변경하지 않았다. `StageObservation`과 `DOENG_STAGE_EVENT` instrumentation을 experiment-only 설정으로 활성화했다.

## 실행 유효성

`DIAG-EXP165-FINITE-001`은 stage snapshot은 있었으나 transport attribution이 비활성이라 request-level stage event가 없어 진단 artifact로만 보존했다.

`DIAG-EXP165-FINITE-002`는 replacement diagnostic으로 유효하다. source provenance, finite batch 조건, stage timeline, request-level event, drain 및 cleanup artifact를 확보했다. 추가 성능 run은 수행하지 않았다.

## HTTP 결과

- 총 요청: 300
- HTTP 200: 299
- HTTP 500/503/504: 0/0/0
- client abort deadline: 1
- connect refused/기타 transport: 0/0
- latency p50/p95/p99/max: 7,026 / 7,790 / 7,970 / 8,100ms

이 수치는 진단 실행의 관찰값이며 성능 SLO 또는 처리량 claim으로 사용하지 않는다.

## Stage residency

| Stage | started | succeeded | failed | cancelled | maxInFlight | p50 / p95 / p99 / max (ms) | peak queue |
|---|---:|---:|---:|---:|---:|---:|---:|
| TOKEN | 300 | 300 | 0 | 0 | 195 | 921.76 / 1,374.09 / 1,406.04 / 1,501.00 | 8 |
| AI | 300 | 300 | 0 | 0 | 300 | 3,165.90 / 3,888.45 / 3,976.30 / 3,983.54 | 0 |
| STORAGE | 300 | 300 | 0 | 0 | 188 | 818.36 / 1,311.94 / 1,391.72 / 1,400.79 | 0 |
| DB | 300 | 299 | 0 | 1 | 219 | 1,000.18 / 1,457.48 / 1,535.44 / 56,239.98 | NOT AVAILABLE |

DB의 56초 max는 정상적인 DB service-rate 분포가 아니라 단일 요청의 장기 residency outlier다. 해당 request에서 `DB_PROGRESS_LOOKUP_OR_CREATE`의 `MappingInstantiationException`과 `memberId must not be null`이 기록됐고, 최종 DB stage는 cancellation으로 종료됐다.

## 1초 service-rate 관찰

- TOKEN: peak 245/s, median 8.75/s
- AI: peak 288/s, median 10.71/s
- STORAGE: peak 180/s, median 6.67/s
- DB: peak 243/s, median 9.00/s

누적 counter 기반 delta이며, stage snapshot이 비어 있는 첫 샘플은 rate 계산에서 자연스럽게 제외했다.

## Drain과 queue

- TOKEN queue는 일시적으로 peak 8까지 관찰됐고 최종 0이다.
- AI active peak 298~300, queue 0.
- STORAGE queue 0.
- DB queue metric은 기존 instrumentation에서 직접 제공되지 않아 `NOT AVAILABLE`이다.
- dispatcher active/queue는 모두 최종 0이다.
- mock AI/storage는 load-stop 시점부터 0이었고 60초 drain 동안 0을 유지했다.
- 가장 늦게 stage inFlight가 0으로 관찰된 것은 DB였다.

## Request path 참고

독립 median을 total median으로 나눈 참고 비율은 TOKEN 13.1%, AI 45.1%, STORAGE 11.6%, DB 14.2%, unattributed 15.9%다. 이는 정확한 요청별 합산 분해가 아니라 stage residency가 제공하는 경계 기반 참고치다. queue-only/network-only 시간을 별도로 분리하지 않았다.

## Bottleneck attribution gate

- TOKEN backlog: `YES_TRANSIENT`
- AI backlog: `NO`
- STORAGE backlog: `NO`
- DB backlog: `NOT AVAILABLE`
- longest residence: `DB_MAX_OUTLIER`
- latest drain stage: `DB`
- lowest completion rate: `DB (299/300)`

## 최종 판정

`PRIMARY_BOTTLENECK_CANDIDATE=INCONCLUSIVE`

AI는 정상 요청의 median residency가 가장 길지만 AI queue/backlog는 없었다. DB는 단일 56초 outlier와 데이터 매핑 예외·cancellation이 있었으나, 이를 DB service capacity 병목으로 일반화할 수 없다. 따라서 현재 진단만으로 TOKEN·AI·STORAGE·DB 중 하나를 확정 병목으로 판정하지 않는다.

## Evidence 범위와 다음 단계

이번 결과는 finite synthetic batch에서 request가 어느 stage 경계에 머물렀는지 설명하는 증거다. “60초를 기다리면 성능이 좋아진다”, “HTTP 200 비율이 높다”, “AI가 병목이다”라는 주장은 이 실행으로 하지 않는다. 추가로 필요하다면 DB mapping failure와 단일 장기 residency를 분리하는 별도 correctness/diagnostic 검증을 설계해야 하며, 본 문서에서는 새 성능 실험을 승인하지 않는다.
