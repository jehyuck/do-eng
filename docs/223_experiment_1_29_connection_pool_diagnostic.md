# Exp129 Reactor Netty Connection Pool 1:1 진단

## 목적

Exp129에서 관찰된 REMEDIATION의 latency·timeout 악화가 connection lifecycle과 직접 연결되는지, 동일한 VU 200 workload에서 pool 수치를 직접 확인했다. 이번 결과는 원인 후보 진단용이며 새로운 성능 캠페인이나 정책 채택 근거가 아니다.

## Collector root cause와 수정

기존 `DIAG-20260805-EXP129-BASELINE-POOL-001`은 HTTP 200 응답을 받았지만 `Invoke-WebRequest` 경로에서 `metrics/providers`가 null로 파싱됐다. 같은 endpoint를 `Invoke-RestMethod`로 직접 조회하면 numeric metric 18개가 반환되는 것을 확인했다.

수정 내용:

- `experiment/scripts/collect-exp129-pool-until-stop.ps1` 추가: `Invoke-RestMethod` 사용
- 1초 간격 JSONL 기록
- 각 행을 독립 JSON object로 기록
- `experiment/scripts/run-exp129-pool-diagnostic.ps1`에서 JSONL을 행 단위로 검증
- 연속 3개 sample에서 provider와 `active/idle/total/pending` numeric metric을 확인하지 못하면 중단
- warm-up ID를 `SMOKE-20260805-EXP129-{condition}-POOL-{runIndex}`로 고정

기존 `POOL-001` 및 warm-up 충돌 artifact는 수정·삭제하지 않았다.

## Smoke gate

- PowerShell syntax: PASS
- `Invoke-RestMethod` collector 경로: PASS
- 연속 3개 numeric sample: PASS
- provider identity: `doeng-external`
- JSONL 행 단위 parse: PASS
- invalid JSONL row: 0
- pending acquire time: `NOT_EXPOSED_BY_CURRENT_METRICS`

## BASELINE-003

- Run: `DIAG-20260805-EXP129-BASELINE-POOL-003`
- Warm-up: `SMOKE-20260805-EXP129-BASELINE-POOL-003`, PASS
- Core: PASS
- Collector samples: 174
- Numeric metric rows: 3,132
- Total peak: 320
- Active peak: 320
- Idle range: 0–320
- Pending peak: 800
- Pending acquire time: `NOT_EXPOSED_BY_CURRENT_METRICS`
- Timeout: 0
- p95: 2,946ms
- p99: 5,229ms
- Time-to-zero: 3,011ms
- Drain: completed
- Cleanup: completed

## REMEDIATION-003

- Run: `DIAG-20260805-EXP129-REMEDIATION-POOL-003`
- Warm-up: `SMOKE-20260805-EXP129-REMEDIATION-POOL-003`, PASS
- Core: PASS
- Collector samples: 168
- Numeric metric rows: 3,024
- Total peak: 320
- Active peak: 286
- Idle range: 0–250
- Pending peak: 800
- Pending acquire time: `NOT_EXPOSED_BY_CURRENT_METRICS`
- Timeout: 109
- p95: 6,108ms
- p99: 7,950ms
- Time-to-zero: 5,008ms
- Drain: completed
- Cleanup: completed

REMEDIATION core와 collector는 정상 완료됐다. 실행 후 summary append 단계에서 PowerShell 객체 배열 결합 오류가 발생했으나, raw client/drain/pool artifact만을 사용해 summary를 복구했으며 부하를 재실행하지 않았다.

## 직접 확인된 현상

- 두 조건 모두 total peak는 320이었다.
- REMEDIATION active peak는 286으로 BASELINE 320보다 낮았다.
- REMEDIATION idle peak는 250으로 BASELINE 320보다 낮았고 두 조건 모두 idle 최솟값은 0이었다.
- 두 조건의 pending peak는 모두 800이었다.
- REMEDIATION의 timeout과 p95/p99는 BASELINE보다 높았다.
- REMEDIATION time-to-zero는 5,008ms로 BASELINE 3,011ms보다 길었다.

## 확인되지 않은 현상

- pending acquire time은 현재 MeterRegistry/endpoint에 노출되지 않았다.
- connection 생성·종료 counter는 endpoint에서 제공되지 않아 churn 횟수는 직접 계산할 수 없다.
- active/idle 감소가 timeout 악화의 원인이라는 인과관계는 이번 1:1 실행만으로 확정할 수 없다.
- 일반 서비스 성능, WebFlux 일반 특성, 운영 환경 결과는 주장하지 않는다.

## 최종 판정

`WARM_CONNECTION_REDUCTION_SUPPORTED`

이번 진단에서는 REMEDIATION에서 관측된 idle peak 감소(320 → 250)와 active peak 감소(320 → 286)가 직접 확인됐다. 이는 LIFO·idle eviction 정책이 warm connection 보유량을 줄이는 현상과 양립한다. 다만 pending peak는 동일했고 timeout·tail latency·drain time-to-zero는 개선되지 않았으므로 성능 개선이나 pool 병목 해소로 확대 해석하지 않는다.

## 산출물

- [diagnostic-summary-003.json](../backend/experiments/results/experiment-1-29/diagnostic-pool-20260805/diagnostic-summary-003.json)
- `backend/experiments/results/experiment-1-29/diagnostic-pool-20260805/baseline-003/pool-timeseries.jsonl`
- `backend/experiments/results/experiment-1-29/diagnostic-pool-20260805/remediation-003/pool-timeseries.jsonl`

Raw diagnostic artifact는 commit하지 않는다.

EXP129_POOL_DIAGNOSTIC_COMPLETED  
ADDITIONAL_PERFORMANCE_CAMPAIGN=NOT_RUN  
NEW_REMEDIATION=NOT_DESIGNED
