# Experiment 1-21 INVALID Closure

## 판정

`RUN-20260803-EXP121-BASELINE-001`은 core invocation까지 시작됐지만 application log capture가 실행 중 컨테이너에서 반환되지 않아 harness 단계에서 중단됐다. 성능 outcome은 closure에서 열람하지 않았다.

- failureDomain: `APPLICATION_LOG_CAPTURE`
- executionStatus: `EXECUTION_FAILED`
- artifactValidation: `FAILED`
- cleanup: `COMPLETED`
- aggregate eligible: `false`
- Experiment 1-21 remaining runs: 실행하지 않음
- policy decision: `NOT_RUN`
- final state: `INVALID`

동일 run ID를 재사용하지 않으며, Exp121 raw artifact는 수정·삭제하지 않고 inventory와 SHA-256을 별도로 보존했다.

## 원인과 후속 경계

기존 순서는 실행 중 application container에서 `docker logs`를 호출했다. 이 단계가 반환되지 않아 terminal artifact를 만들 수 없었다. Exp122에서는 collector 종료와 coverage 생성 후 application container만 stop하고, stopped/exited 상태를 확인한 뒤 post-stop snapshot을 수행한다. timeout은 별도 failure domain으로 보존한다.

성능 비교, RPS, latency, HTTP 결과, pool 값, application log 내용은 이번 closure에서 해석하지 않았다.
