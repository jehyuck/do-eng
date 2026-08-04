# Experiment 1-23 INVALID Closure

- 기준 HEAD: a5a783f0cf6c6d0d0c4fe3996c6d07b006765be0
- run: RUN-20260804-EXP123-BASELINE-001
- warm-up/core/collector readiness/coverage: 완료
- 실패 단계: application container stop metadata persistence
- failureDomain: ARTIFACT_FINALIZATION
- failureType: CONTAINER_STOP_METADATA_PARENT_DIRECTORY_MISSING
- container stop 및 post-stop capture: 미완료
- aggregate eligible: false
- policyDecision: NOT_RUN
- 재실행 및 잔여 Exp123 run: 금지

Closure는 raw outcome을 해석하지 않으며, 원본 artifact는 실행 clone에 보존한다.

