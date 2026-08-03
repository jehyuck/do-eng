# Experiment 1-22 Native Process / Timeout / Large Artifact Gate

## 정합화 내용

- capture는 `.NET Process`로 실행하고 실제 process `ExitCode`를 보존한다.
- 정상 종료는 `timedOut=false`, 실제 `exitCode=0`일 때만 PASS다.
- non-zero exit은 `APPLICATION_LOG_CAPTURE_FAILED`로 분류한다.
- timeout은 `APPLICATION_LOG_CAPTURE_TIMEOUT`으로 분류하고 partial stdout/stderr와 termination 시도·확인 여부를 보존한다.
- application stop은 별도 `experiment-1-22-container-stop.ps1` helper를 사용하며 graceful stop 15초와 CLI process timeout 30초를 분리한다.
- stop timeout/non-zero/correct stopped state를 별도 metadata와 failure domain으로 기록한다.
- 대용량 raw log byte 검증은 `FileInfo.Length`만 사용하며 `ReadAllBytes`/`ReadAllText`를 사용하지 않는다.
- aggregator는 Experiment 1-22 ID와 stop/capture contract를 함께 확인한다.

## Fixture 결과

- Fixture A: capture exit 0 PASS
- Fixture B: capture exit 7 PASS
- Fixture C: capture timeout PASS
- Fixture D: stop exit 0 PASS
- Fixture E: stop non-zero PASS
- Fixture F: stop timeout PASS
- Fixture G: 200MB metadata-only size validation PASS

## Readiness

BASELINE/REMEDIATION post-stop preflight와 Exp122 PLAN을 재실행했다. warm-up/k6/core는 0이며 최종 상태는 `EXP122_READY_FOR_SIX_CORE_RUNS`다.

이번 작업에서는 성능 실행, outcome 분석, policy decision을 수행하지 않았다.
