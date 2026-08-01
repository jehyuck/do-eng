# DoEng Experiment 1-3 Final Result

## Experiment status

- Experiment 1-1: CLOSED
- Experiment 1-2: CLOSED (`C — CONTROL INSUFFICIENT`)
- Experiment 1-3: CLOSED after one diagnostic scout and one remediation

## Diagnostic finding

The current corrected REST path shared one Reactor Netty outbound provider across
token, AI and HTTP storage. At VU200/pool400 the provider reached 400 active
connections and the pending-acquire limit; the server emitted
`PoolAcquirePendingLimitException` and returned HTTP 500. This is supported as
R5 shared outbound resource interference.

## Source changes

- Added opt-in `StageObservation` counters and `/actuator/doengstages` endpoint.
- Added targeted stage collector and Experiment 1-3 diagnostic/core wrappers.
- Moved the existing `AiOutboundAdmissionGate` boundary around the full
  token→AI→storage→DB publisher. No pool, worker, timeout, scheduler, CPU,
  memory, retry, fallback, or workload setting changed.
- Added focused stage observer tests; diagnostic flags remain OFF by default.

## Tests and build gate

JDK11/Gradle test gate passed after the change (`BUILD SUCCESSFUL`). Existing
tests plus `StageObservationTest` passed. The diagnostic image built successfully.

## Independent variable

Only the admission-boundary scope changed: AI-only boundary → complete outbound
request path. Admission limit remained 320.

## Frozen contract verification

All three core runs used WebFlux, VU200, AI 2,000 ms, storage 100 ms, 1 s
frame/reconnect, 105 s measurement, 10 s client timeout, 2 CPU/3 GiB,
HTTP pool400, DB pool10, fresh JVM, same fixture/auth/DB/storage contract,
JFR OFF, comprehensive snapshots OFF, DB/container monitors ON, load-stop and
30 s drain ON. Controlled 503 responses were treated as system outcomes.

## Diagnostic scout

`RUN-20260801-EXP13-DIAG-002` is diagnostic-only and directly captured 11,755
`PoolAcquirePendingLimitException` occurrences, pool active max 400, sampled
pending max ~1,700, and stage attribution. `RUN-20260801-EXP13-DIAG-001` is a
retained setup failure caused by the incorrect root URL and is excluded.

## Valid core runs

| Run | HTTP200 | HTTP503 (controlled) | Uncontrolled failure | p95 | p99 | RPS | Pool exception | Drain | Valid |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| RUN-20260801-EXP13-CORE-001 | 451 | 318 | 0 | 4,157 ms | 4,526 ms | 7.32 | 0 | 0 ms / complete | VALID |
| RUN-20260801-EXP13-CORE-002 | 430 | 275 | 0 | 3,734 ms | 3,823 ms | 6.71 | 0 | 0 ms / complete | VALID |
| RUN-20260801-EXP13-CORE-003 | 419 | 278 | 0 | 3,733 ms | 3,833 ms | 6.64 | 0 | 0 ms / complete | VALID |

The mock snapshots for all three runs recorded balanced external in-flight
drain and the admission endpoint after the final fresh JVM recorded
`maxObservedInUse=320`, `currentInUse=0`, and `permitLeak=0`. The gate's release
tests also passed. Controlled rejections were 503s, not server 500s.

## Result classification

**A — REACTIVE PATH STABILIZED (within the fixed synthetic VU200 envelope).**

The first confirmed remediation prevented uncontrolled HTTP 500/pending-limit
failures in three VALID runs without changing the resource or pool contract.

## What was proved

- The prior HTTP 500 failure mode was directly associated with shared outbound
  pool pending-acquire pressure.
- Extending the existing admission boundary to the complete outbound path
  prevented uncontrolled failures under the fixed envelope.
- Permit lifecycle remained balanced and storage/DB completion remained correct.

## What was not proved

- WebFlux is not proven universally faster or superior to MVC.
- No production capacity limit or general VU ceiling was established.
- Base64/event-loop CPU was not proven dominant or absent in all workloads.
- The remediation does not prove that every future external failure has the
  same cause; it establishes support for this observed failure mode.

## Existing MVC context

Existing MVC400 runs remain historical context only. Experiment 1-3 did not
execute MVC and does not create a new controlled WebFlux/MVC comparison.

## Portfolio-safe claim

Under a fixed synthetic VU200 envelope, the corrected WebFlux REST path showed a
shared outbound pool pending-acquire failure mode; a single, evidence-gated
admission-boundary correction converted uncontrolled 500s into explicit
controlled 503 outcomes across three VALID runs. This is an implementation-path
and resilience claim, not a universal framework superiority claim.

## Evidence paths

- Source audit: `docs/97_experiment_1_3_source_audit_20260801.md`
- Diagnostic result: `docs/98_experiment_1_3_diagnostic_result_20260801.md`
- Raw diagnostic: `experiment/results/RUN-20260801-EXP13-DIAG-002/`
- Raw core runs: `experiment/results/RUN-20260801-EXP13-CORE-001/` through `003/`
- Ledger addendum: `docs/11_run_ledger_exp13_addendum.md`

## Final state

No second remediation, tuning sweep, MVC run, VU sweep, or production-capacity
claim was performed.
