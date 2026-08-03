# Experiment 1-19 Frozen Mock Image Binding Recovery

## 실패 artifact

`RUN-20260803-EXP119-BASELINE-001`은 fresh recreate 단계에서 중단됐다. warm-up, core, k6, drain, verification은 시작되지 않았고 `EXECUTION_FAILED`와 `failure-summary.json`만 생성됐다.

원인은 preflight의 project-scoped mock tag와 core Compose project가 요구한 tag가 달랐기 때문이다.

## invalid pre-run 보존

원본은 [invalid-pre-run artifact](/D:/T7/workspace_작업공간/50_로컬레포/active/projects/jehyuck/do-eng/backend/experiments/results/experiment-1-19/invalid-pre-run/RUN-20260803-EXP119-BASELINE-001-attempt-001-mock-image-binding)로 이동했다.

`attempt-disposition.json`은 `PRE_MEASUREMENT_HARNESS_FAILURE`, `measurementStarted=false`, `ARCHIVED_NOT_COUNTED_AS_CORE_RUN`을 기록한다. active core 경로에는 이 run artifact가 없다.

## Stable mock tag

frozen digest를 재빌드하지 않고 다음 local alias만 만들고 검증했다.

```text
doeng-exp119-mock-frozen-20260803:latest
→ sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1
```

## Compose·runner binding

`experiment-mock`에 explicit `image`와 Compose `!reset null` build override를 추가했다. rendered Compose에서 build가 실제로 제거되는 것을 확인했다. preflight와 core runner 모두 동일한 stable tag를 `DOENG_EXP119_MOCK_IMAGE`로 주입하고, 실행 전 tag ID가 frozen digest와 같은지 확인한다.

provenance와 manifest에는 `mockImageTag`, `mockImageId`, `mockImageBindingMode=EXPLICIT_FROZEN_TAG`를 기록한다. application image, lifecycle policy, workload, pool, run order는 변경하지 않았다.

## Controlled diff

두 arm preflight를 fresh recreate로 수행했다.

- stable mock tag와 digest 일치
- application image 일치
- mock image·build 설정 양 arm 동일
- controlled lifecycle diff만 유지
- preflight readiness: `READY_FOR_SIX_CORE_RUNS`

## PLAN 결과

6개 manifest를 고정 순서로 재생성했다. stable binding이 각 manifest에 기록됐고, warm-up·k6·core·client result·run directory는 0이다.

## 실제 실행 횟수

이번 recovery 작업에서 warm-up, core, k6는 실행하지 않았다.

## 최종 판정

`CORE_EXECUTION_RECOVERY_READY`

이는 실행 복구 준비 상태이며, 정책 효과·성능·measurement validity를 의미하지 않는다.
