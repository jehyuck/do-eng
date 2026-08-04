# Experiment 1-25 INVALID 종료 — Pool Collector Timeout

## 판정

- Experiment 1-25: `INVALID`
- 분류: `MEASUREMENT_EXECUTED_OBSERVER_COVERAGE_FAILED`
- failureDomain: `POOL_COLLECTOR`
- failureType: `POOL_COLLECTOR_POLL_TIMEOUT`
- policyDecision: `NOT_RUN`
- Exp125 동일 run ID 재실행: 금지

## 보존 원본

| 원본 | SHA-256 |
|---|---|
| `backend/experiments/results/experiment-1-25/core/RUN-20260804-EXP125-BASELINE-001/run-config.json` | `65e7450be1a96202c40dea7f93ca28d562195db944f75861d4179bfd430ad5c7` |
| `backend/experiments/results/experiment-1-25/core/RUN-20260804-EXP125-BASELINE-001/failure-summary.json` | `2c5a36390034da3b0a4ba9defd238de53e8aad85a476442c60965145a6c175a9` |
| `backend/experiments/results/experiment-1-25/core/RUN-20260804-EXP125-BASELINE-001/execution-summary.json` | `350d08db248eef8425118a7993f24f7f1ac130527380ec8c16799d0694ccebe8` |
| `backend/experiments/results/experiment-1-25/collector-staging/RUN-20260804-EXP125-BASELINE-001/pool-metrics.jsonl` | `150c940d38b3e4046bf24f25fa335ad7eee37d5f340941c15636234515321cba` |
| `backend/experiments/results/experiment-1-25/collector-staging/RUN-20260804-EXP125-BASELINE-001/pool-metrics.jsonl.summary.json` | `612ba59531a1c421d96adb9ce78c41e02c36cf8a167a2c00f83a311340a37410` |
| `backend/experiments/results/experiment-1-25/plan/runner-readiness.json` | `1fca0df60ebd2e38006b4f3701dbb3e28d561be1c03c8201b0693695fdfe66f6` |

The collector preserved 117 successful samples and one timeout at `2026-08-04T10:57:37.1830944Z`; therefore the run is not eligible for aggregate use.

## Exp126 boundary

Exp126은 성능 정책·workload·resource를 변경하지 않는다. 목적은 collector의 timeout/failure 기록과 loop recovery를 검증하는 것뿐이며, warm-up/k6/core를 수행하지 않는다.
