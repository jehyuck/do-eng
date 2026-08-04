# Experiment 1-26 Readiness

## 상태

상태: `EXP126_READY_FOR_SIX_CORE_RUNS`

필수 gate:

- Exp125 INVALID closure 및 raw inventory 보존
- idle collector 300초, failure 0
- Z1~Z8 reliability fixture 통과
- BASELINE/REMEDIATION production-path probe 통과
- synthetic aggregator fixture 통과
- Exp126 six-core PLAN 통과
- startedRuns/warmupInvocations/coreInvocations/k6Invocations 모두 0

성능 결과나 정책 decision은 이 문서에서 다루지 않는다.

## Gate 결과

- Exp125 closure/raw inventory: 통과
- Z1~Z8 reliability fixture: 통과
- BASELINE idle production-path probe: 통과, 300초, collector failures 0
- REMEDIATION idle production-path probe: 통과, 300초, collector failures 0
- synthetic six-run aggregator fixture: 통과
- Exp126 six-core PLAN: 통과
- startedRuns: 0
- warmupInvocations: 0
- coreInvocations: 0
- k6Invocations: 0
- policyDecision: `NOT_RUN`

초기 recovery probe의 readiness 파일 부재와 max-duration 경계 종료는 각각 보존된 실패 artifact로 남기며, 최종 recovery probe 결과와 혼합하지 않는다.
