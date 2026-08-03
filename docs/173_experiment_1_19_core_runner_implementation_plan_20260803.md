# Experiment 1-19 six-core runner 구현 계획

상태: 구현 및 PLAN 검증

## 현재 공백

기존 1-19 runner는 preflight 전용이었다. Exp113 core runner는 이미지·condition·artifact 경로가 고정돼 재사용할 수 없었다.

## 구현

- `run-experiment-1-19-core.ps1`: `Condition`, `RunIndex`, `ExecutionMode=PLAN|EXECUTE`를 받는다. 기본은 PLAN이다.
- `run-experiment-1-19-six-core.ps1`: BASELINE-001, REMEDIATION-001, BASELINE-002, REMEDIATION-002, BASELINE-003, REMEDIATION-003 순서만 지원한다.
- PLAN은 image inspect, 파일/경로/ID 검증과 manifest 작성만 한다.
- EXECUTE는 기존 1-13 smoke, fixture/auth, monitor, load-stop/drain, consistency primitive를 frozen 1-19 Compose/policy로 호출하도록 구현했다.

## 고정 조건

application source `270349fa`, app image `sha256:c287…d9168`, mock image `sha256:2492…29ac1`, VU 200, 105초, 1초 frame/reconnect, AI 2,000ms, storage 100ms, timeout 10초, drain 30초, app 2CPU/3GiB, pool 400/800, DB pool 10, admission 320을 변경하지 않는다.

## Hard stop

이번 단계에서는 PLAN만 실행한다. Docker compose up, reset, fixture 생성, warm-up, k6, core, drain, analysis를 실행하지 않는다.
