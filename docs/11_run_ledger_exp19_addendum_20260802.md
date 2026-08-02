# Experiment 1-9 run ledger addendum

기준 branch: `experiment/doeng-reactive-overload-control`

기준 source commit: `4eb3495` (실험: reactive admission 관찰 및 강제 모드 추가)

실행 경로 보정 commit: `7f823a8` (실험: overload control runner 인자 연속성 수정)

limit 사전 등록: `docs/143_experiment_1_9_limit_preregistration_20260802.md`

| Run | Arm | Measurement validity | 주요 처리 | 비고 |
|---|---|---|---|---|
| `RUN-20260802-EXP19-OBSERVE-001` | OBSERVE | INVALID | raw/load/drain 보존 | admission/stage Actuator 조회가 각각 1회 10초 timeout. collector instrumentation failure로 aggregate 제외 |
| `RUN-20260802-EXP19-OBSERVE-002` | OBSERVE | VALID | successful 11,022, HTTP500 8,049, timeout 1,595 | max in-flight 1,576, wouldReject 20,346, pool active 400/pending max 1,419, leak 0 |
| `RUN-20260802-EXP19-OBSERVE-003` | OBSERVE | VALID | successful 13,880, HTTP500 6,201, timeout 589 | max in-flight 1,435, wouldReject 20,350, pool active 400/pending max 1,043, leak 0 |
| `RUN-20260802-EXP19-OBSERVE-004` | OBSERVE | VALID | successful 698, HTTP500 15,053, timeout 4,608, connection error 57 | max in-flight 1,848, wouldReject 20,039, pool active 400/pending max 1,892, leak 0 |
| `RUN-20260802-EXP19-ENFORCE-001` | ENFORCE/320 | VALID | successful 4,843, admission503 6,220, HTTP500 24, timeout 1,588, connection error 6,863 | max in-flight 320, rejected 6,506, pool pending max 18, leak 0 |
| `RUN-20260802-EXP19-ENFORCE-002` | ENFORCE/320 | VALID | successful 12,930, admission503 7,737, HTTP500 0 | max in-flight 320, pool pending max 3, drain 3,006 ms, leak 0 |
| `RUN-20260802-EXP19-ENFORCE-003` | ENFORCE/320 | VALID | successful 12,917, admission503 7,724, HTTP500 0 | max in-flight 320, pool pending max 3, drain 3,004 ms, leak 0 |

높은 HTTP error, backlog, drain 시간은 validity가 아니라 system outcome으로 보존했다. 최종 aggregate에는 위 VALID 6개만 사용하며 INVALID OBSERVE-001은 제외하되 raw를 삭제하지 않는다.
