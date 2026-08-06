# Experiment 1-48 Plan

## Question

Does the Factor A transaction write-order change preserve rollback atomicity, and how much does stage observation change the fixed A1B0 workload measurements?

## Fixed conditions

200 active missions, 1s interval/reconnect, 30s load, 10s request timeout, 30s drain, AI 2s, storage 100ms, application 2 CPU/3GiB, mock 4 CPU/1GiB, DB 1 CPU/1GiB, shared WebClient pool 500/pending 800, Admission OFF, same fixture/token/scene and R2DBC pool.

## Cells

- Phase 1: actual Spring R2DBC transaction atomicity integration test.
- A1B0-P: stage observation OFF, minimal start/end pool/R2DBC snapshots.
- A1B0-D: stage observation ON, existing 1s stage/pool/R2DBC diagnostics.

Performance runs are executed before diagnostic runs with fresh cleanup between cells. No pool, workload, retry, admission, SQL, or WebClient behavior changes are allowed.

## Decision

Atomicity is `FACTOR_A_ATOMICITY_VALIDATED`, `FACTOR_A_ATOMICITY_FAILED`, or `FACTOR_A_ATOMICITY_NOT_TESTABLE`. Observation overhead is `OBSERVATION_OVERHEAD_LOW`, `OBSERVATION_OVERHEAD_MATERIAL`, or `OBSERVATION_OVERHEAD_SEVERE` using the preregistered 5% and 15% operational thresholds; this is not a statistical significance claim.

## Artifacts

`backend/experiments/results/experiment-1-48/a1b0-observation-calibration/` and the two analysis files specified by the execution prompt. Raw artifacts are not committed.
