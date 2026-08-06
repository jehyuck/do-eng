# Exp141 Next Pool Candidate

## 선택값

`500`

## 선택 근거

현재 controlled 관측은 Pool400과 Pool1000 모두 active 상한 도달을 보여준다. 따라서 400에서 1000으로 크게 건너뛴 현재 곡선 사이의 첫 50 단위 후보인 500을 선택하는 것이 경계 위치를 가장 작게 이동해 확인하는 방법이다.

- Pool400: active 400, pending 1,365, pending-limit exception 4,868
- Pool1000: active 1,000, pending 905, pending-limit exception 718
- 두 current run 모두 단일 관측이므로 500을 운영 권장값으로 해석하지 않는다.

## 예상 비교 구간

- 동일 current workload에서 Pool400/Pool1000과 대칭적인 단일 run
- maxConnections만 500
- pending 800, timeout, CPU/memory, mock delay, Admission OFF, collector, fixture, accounting 유지
- 판정은 successful RPS, uncontrolled HTTP500/timeout/connection-error 비율, p95, active/pending, memory/OOM을 함께 사용

## Evidence gap

Pool500 실행 raw와 Pool600·700·750·800 raw가 현재 저장소에서 확인되지 않는다. 문서에 남은 “pool500/greater closed” 기록은 실행 artifact를 대체하지 않으므로, 500은 아직 `NEXT_CANDIDATE`, 결과가 아니다.

## 제한

Exp141 자체에서는 신규 실행을 하지 않았다. 다음 후보 실행은 별도 계획 승인과 새 run ID가 필요하다. 기존 Exp139·Exp140 raw와 이 문서의 판단은 변경하지 않는다.
