# Experiment 1-19 core execution contract

## DECISION

`CORE_RUNNER_READY`

## SOURCE COMMIT

`270349fa7937eb4486087d34184461ae6aaab10a`

## HARNESS HEAD

현재 branch HEAD 기준 runner 구현 commit으로 provenance를 고정한다.

## RUNNER STATE

PLAN/EXECUTE 분리, 기본 PLAN.

## ORDERED RUNS

BASELINE-001 → REMEDIATION-001 → BASELINE-002 → REMEDIATION-002 → BASELINE-003 → REMEDIATION-003

## FROZEN IMAGES

app `sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168`; mock `sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1`.

## WORKLOAD CONTRACT

VU 200, 105초, frame/reconnect 1초, AI 2,000ms, storage 100ms, timeout 10초, drain 30초, app 2CPU/3GiB, pool 400/800, DB pool 10, admission 320.

## PRE-RUN GATES

source/image/config provenance, artifact nonexistence, health, mock idle/reset, DB reset, fixture/auth, collector 경로를 확인한다.

## EXECUTION STEPS

fresh recreate → gate → warm-up → core → load-stop/drain → consistency → artifact check → cleanup.

## ARTIFACT CONTRACT

run-config, client result/progress, pool, application, DB/container, mock/drain, verification, provenance, execution summary를 요구한다.

## FAILURE SEMANTICS

infrastructure/contract failure면 해당 run에서 중단하고 이후 run을 실행하지 않는다. 성능 수치는 system outcome이다.

## CURRENT EXECUTION COUNT

0

## NEXT ALLOWED STEP

별도 승인 뒤 BASELINE-001 EXECUTE.

## HARD STOP

이번 단계에서 warm-up, k6, core, 결과 분석, policy decision은 실행하지 않았다.
