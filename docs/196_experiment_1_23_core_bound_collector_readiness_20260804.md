# Experiment 1-23 Harness Readiness

## 구현

- core-bound stop-signal collector
- post-core covering sample gate
- atomic `STOP-COLLECTOR.tmp` rename
- collector lifecycle Evidence
- Exp123 artifact contract와 aggregator identity
- terminal marker 전환 경로

## Outcome-blind fixture

Fixture A readiness, B post-core sample, C graceful stop, D post-core timeout, E max duration, F stop timeout, G summary failure, H terminal failure, I completed state를 검증 대상으로 등록했다.

현재 실제 warm-up·k6·core는 실행하지 않았다. collector-only probe와 PLAN 검증 후 `EXP123_READY_FOR_SIX_CORE_RUNS`를 목표 상태로 사용한다.
