# Experiment 1-29 최종 정책 판정

## 1. 실험 질문

고정된 synthetic WebFlux workload에서 outbound HTTP connection lifecycle 정책을 변경했을 때 요청 성능과 종료·회수 동작이 반복적으로 개선되는지 확인했다.

## 2. 비교 조건

- BASELINE: FIFO / 무제한 유지 정책
- REMEDIATION: LIFO / idle 3초 / eviction 1초 정책
- 선택된 각 조건 3회
- 동일한 workload, fixture, image, collector 및 runtime 조건
- 추가 부하 실행 없음

## 3. 최종 3:3 선택 세트

BASELINE은 `RUN-20260806-EXP129-BASELINE-001`, `-002`, `-003`을 사용했다.

REMEDIATION은 `RUN-20260806-EXP129-REMEDIATION-001`, `-002`, `-004`를 사용했다. `REMEDIATION-003`은 `EXECUTION_FAILED`, `COLLECTOR_COVERAGE_INVALID`, `maximumValidSampleGapMilliseconds=8861.206 > 8000`으로 제외됐다.

상세 원본값과 계산 결과는 [aggregate-20260806.json](../backend/experiments/results/experiment-1-29/aggregate-20260806.json)에 보존했다.

## 4. Validity와 limitation

최종 선택 세트의 validity는 `EXP129_FINAL_SET_VALID_WITH_LIMITATION`이며, 기준 commit은 `2bfbeb805a6a4aeb7ce0b52a62608a4ca20b1477`이다. `REMEDIATION-001`의 bounded transient collector loss는 Validity Audit에서 유효로 판정됐고, collector timeout row를 사용자 요청 실패로 계산하지 않았다.

REMEDIATION-004는 harness-only 변경 상태에서 실행됐으며 raw artifact에 독립적인 dirty-tree provenance가 남지 않았다. 다만 frozen application/mock image, workload, collector 설정, compose provenance와 runtime configuration의 동등성은 Validity Audit에서 확인됐다.

사전 통계 기준은 없으므로 통계적 유의성은 주장하지 않는다.

## 5. run별 원본 결과

| 조건/run | 총 요청 | 성공률 | 처리량 req/s | 전체 p95/p99 ms | accepted p95/p99 ms | timeout | HTTP 오류 | HTTP 503 | load-stop 미완료 | time-to-zero ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| BASELINE-001 | 20,611 | 37.21% | 196.30 | 5,608 / 8,050 | 6,889 / 9,256 | 561 | 339 | 12,042 | 374 | 3,003 |
| BASELINE-002 | 20,667 | 48.90% | 196.83 | 4,378 / 8,365 | 4,532 / 9,056 | 232 | 212 | 10,116 | 463 | 3,000 |
| BASELINE-003 | 20,665 | 52.40% | 196.81 | 4,094 / 5,541 | 4,630 / 6,112 | 0 | 0 | 9,837 | 303 | 3,014 |
| REMEDIATION-001 | 19,593 | 13.14% | 186.60 | 9,182 / 9,854 | 9,801 / 10,000 | 2,628 | 12 | 9,458 | 614 | 7,000 |
| REMEDIATION-002 | 20,666 | 41.66% | 196.82 | 5,792 / 7,198 | 6,525 / 7,955 | 24 | 0 | 12,032 | 463 | 4,004 |
| REMEDIATION-004 | 20,443 | 17.31% | 194.70 | 8,742 / 9,705 | 9,595 / 9,931 | 2,075 | 26 | 11,257 | 481 | 6,010 |

모든 선택 run에서 최종 미완료 backlog는 0이고 `drainCompleted=true`였다.

## 6. 조건별 집계

| 지표 | BASELINE 중앙값 (min–max) | REMEDIATION 중앙값 (min–max) | 해석 |
|---|---:|---:|---|
| 성공률 | 48.90% (37.21–52.40) | 17.31% (13.14–41.66) | remediation 낮음 |
| 처리량 | 196.81 (196.30–196.83) | 194.70 (186.60–196.82) | remediation 소폭 낮음, 편차 큼 |
| 전체 p95 | 4,378 ms (4,094–5,608) | 8,742 ms (5,792–9,182) | remediation 높음 |
| 전체 p99 | 8,050 ms (5,541–8,365) | 9,705 ms (7,198–9,854) | remediation 높음 |
| accepted p95 | 4,630 ms (4,532–6,889) | 9,595 ms (6,525–9,801) | remediation 높음 |
| accepted p99 | 9,056 ms (6,112–9,256) | 9,931 ms (7,955–10,000) | remediation 높음 |
| timeout | 232 (0–561) | 2,075 (24–2,628) | remediation 높음 |
| load-stop 미완료 | 374 (303–463) | 481 (463–614) | remediation 소폭 높음 |
| time-to-zero | 3,003 ms (3,000–3,014) | 6,010 ms (4,004–7,000) | remediation 개선 아님 |

## 7. 요청 성능 비교

요청 결과 기준으로 remediation은 개선되지 않았다. 중앙값 성공률은 48.90%에서 17.31%로 낮아졌고, 전체 p95는 4,378ms에서 8,742ms로, accepted p95는 4,630ms에서 9,595ms로 높아졌다. 중앙값 timeout도 232건에서 2,075건으로 증가했다. REMEDIATION-002 한 회는 상대적으로 양호했지만 세 회의 방향이 일관되지 않았고, 나머지 두 remediation run에서 악화가 반복됐다.

## 8. 자원·pool 비교

선택 artifact의 pool JSONL에는 active/idle/pending/max pending의 수치가 없고 collector 응답 메타데이터만 남아 있었다. 따라서 connection pool 지표는 `NOT_AVAILABLE`이며 다른 값으로 추론하지 않았다.

Application container CPU 중앙값은 BASELINE run에서 약 201–202%, REMEDIATION run에서 약 202–210%로 remediation 쪽이 다소 높았으나 범위가 겹치고 원인성을 설명할 정도의 차이로 해석하지 않는다. memory와 PID도 run 간 범위가 겹쳤으며, 이 자료만으로 자원 병목을 특정할 수 없다.

## 9. drain·회수 비교

6개 run 모두 drain이 완료됐고 최종 AI/storage backlog는 0이었다. 따라서 remediation이 최종 정합성을 회복했다는 차이는 확인되지 않는다. 오히려 부하 종료 후 zero 도달 중앙값은 BASELINE 3,003ms에서 REMEDIATION 6,010ms로 길어졌고, load-stop 시점 미완료 backlog 중앙값도 374에서 481로 늘었다. 선택 artifact에는 connection active/idle 회수 수치가 없어 connection 회수 속도의 개선은 확인할 수 없다.

## 10. 최종 판정

`REMEDIATION_REGRESSION`

판정 근거는 요청 결과의 반복적인 악화다. 성공률, tail latency, timeout, 처리량이 조건 중앙값 기준으로 remediation에 불리했고, drain 완료와 backlog 0은 양 조건 모두에서 동일했다. lifecycle recovery만 개선됐다고 볼 근거도 없으며, pool 수치가 없어 connection 회수 개선을 별도로 입증할 수도 없다.

## 11. 주장 가능한 범위

이번 결과로 주장할 수 있는 범위는 다음으로 제한한다.

> 고정된 synthetic WebFlux workload에서 FIFO/무제한 유지 정책과 LIFO/idle 3초/eviction 1초 정책을 각각 3회 비교한 결과, 이번 조건에서는 remediation 정책이 요청 성공률과 tail latency를 개선하지 못했고 drain time-to-zero도 짧아지지 않았다.

이는 해당 synthetic workload에서의 관찰이며 WebFlux가 MVC보다 우수하다거나, LIFO가 모든 운영 서비스에 적합하다는 의미는 아니다.

## 12. 포트폴리오용 안전한 결론

고정된 synthetic workload에서 outbound connection lifecycle 정책을 3회씩 비교해 정책 효과를 검증했다. 이번 조건에서는 LIFO·idle eviction 정책이 성공률과 tail latency를 개선하지 못했고, timeout과 drain time-to-zero가 오히려 증가했다. 따라서 해당 정책을 일반 해법으로 채택하지 않고, pool active/idle/pending을 직접 수집하는 계측 보강이 선행되어야 한다는 결론으로 범위를 제한한다.

추가 부하 실행은 필요하지 않으며, 이 문서로 Experiment 1-29 캠페인을 종료한다.

EXP129_AGGREGATE_COMPLETED  
EXP129_POLICY_DECISION_COMPLETED  
ADDITIONAL_LOAD_EXECUTION=NOT_REQUIRED  
EXPERIMENT_CAMPAIGN=CLOSED
