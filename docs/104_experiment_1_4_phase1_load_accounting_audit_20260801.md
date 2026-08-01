# Experiment 1-4 Phase 1 — Load and Accounting Audit

Date: 2026-08-01

## Scope

This audit is limited to the measurement harness. The WebFlux business path,
full-path admission gate, pool/resource settings, fixture, mock delays, DB
contract and workload parameters remain unchanged.

## Finding

The previous `single-success` driver stopped a VU after its first HTTP 200.
That made the offered load success-dependent and made the prior throughput
population a completed-request count rather than a constant one-second frame
contract. The previous results remain preserved; they are not rewritten.

The corrected mode keeps every VU active through the complete 105-second
measurement window. Each one-second scheduling opportunity creates at most one
request, and HTTP 200/503/500, timeout, abort and connection outcomes do not
cause an immediate retry. Normal pacing continues until load stop.

## Files changed

- `experiment/load/mission-load.js`
- `experiment/load/mission-load.accounting.test.js`
- `experiment/scripts/run-isolated-vu-success-smoke.ps1`
- `experiment/scripts/run-experiment-1-4-before.ps1`
- `backend/docker-compose.experiment-1-4-before.yaml`

## Build and test gate

- Node syntax checks: PASS.
- Corrected accounting harness test: PASS.
- Docker JDK 11 / Gradle 7.6.1 `test`: PASS.
- No performance run was executed during this audit.

## Runtime preflight

The new observation-only overlay was recreated without load. Health and the
stage, pool and admission endpoints returned successfully; pre-run mock
in-flight was 0/0. This confirms endpoint and compose mapping before the scout.

## Interim checkpoint

`LOAD-AND-ACCOUNTING AUDIT PASS` — implementation is ready for one diagnostic
scout. No Phase 1 core run has yet been included in the baseline.
