# DoEng Experiment 1-5 - Preregistered Design

Status: DESIGN ONLY. No source change, build, Docker image build, load run,
commit, push, or MVC comparison was performed for this experiment.

## 1. Design decision

**PROCEED WITH 352**.

The decision is limited to a one-variable calibration experiment. It does not
claim that 352 is optimal or that WebFlux is superior to MVC.

## 2. Source of truth reviewed

- `docs/99_experiment_1_3_final_result_20260801.md`
- `docs/111_experiment_1_4_phase1r_observer_recovery_result_20260801.md`
- `docs/112_experiment_1_4_phase1r_corrected_before_closure_20260801.md`
- `docs/113_experiment_1_4_phase1r_after_threshold_freeze_20260801.md`
- `docs/115_experiment_1_4_phase2_source_audit_20260801.md`
- `docs/118_experiment_1_4_phase2_scout_result_20260801.md`
- `docs/119_experiment_1_4_phase2_after_result_20260801.md`
- `docs/121_experiment_1_4_phase2_final_result_20260801.md`
- Phase 1-R raw runs `BEFORE-003/004/005` and their ledger addendum

The filenames in the supplied prompt differed from the repository filenames;
the repository documents above were used.

## 3. Preserved Phase 2 result

Experiment 1-4 Phase 2 remains closed as `E - CONTROL INSUFFICIENT OR NEW
BOTTLENECK`. Per-outbound mode was measurement-valid and leak-free, but did
not improve the preregistered capacity targets. No Phase 2 tuning is being
reinterpreted as evidence for this experiment.

## 4. Current full-path-320 state

Corrected BEFORE aggregate from three valid runs:

| Measure | Median | Range |
|---|---:|---:|
| Successful HTTP200 throughput | 112.7429 RPS | 110.1714-120.7619 |
| Controlled 503 rate | 42.689% | 38.625%-43.928% |
| Accepted p95 | 3,876 ms | 3,162-5,160 ms |

All three runs had max permit in-use 320, acquired=released, permit leak 0,
drain pass, DB/storage consistency pass, and no uncontrolled HTTP500.

## 5. Permit occupancy evidence

The final admission snapshots were:

| Run | Acquired | Rejected | Released | Max in-use | Leak |
|---|---:|---:|---:|---:|---:|
| BEFORE-003 | 11,649 | 9,067 | 11,649 | 320 | 0 |
| BEFORE-004 | 12,760 | 7,980 | 12,760 | 320 | 0 |
| BEFORE-005 | 11,918 | 8,819 | 11,918 | 320 | 0 |

This directly supports that the full-path gate reached its configured limit
and rejected work. It does not establish that every rejection was the only
capacity bottleneck.

## 6. Pool headroom evidence

Across the preserved pool time series, active connections reached 320, while
the configured pool maximum was 400. Maximum observed pending connections were
9, 17, and 12 respectively; maximum pending was configured as 800. Pool
collector failures were zero. Thus the raw evidence shows headroom at the
observed boundary, subject to sampling granularity; it does not prove that a
352 run has 48 connections of guaranteed safe headroom.

## 7. Stage and resource evidence

The BEFORE contract is full-path admission, so stage counters are not used as
the independent-variable basis. Pool, admission, DB, container, drain, and
correctness artifacts are retained. The application container remained within
the 3 GiB memory limit (a representative sample was 571 MiB / 3 GiB); the
observed CPU and database artifacts do not provide evidence of a hard shared
resource ceiling before permit exhaustion. Any resource saturation discovered
in the 352 run is a result, not a reason to change the contract.

## 8. Candidate 352 calculation

The preregistered heuristic is:

`320 * (124.0172 / 112.7429) = 351.94`, rounded to **352**.

This is a candidate calibration point, not a model-derived optimum. The
experiment will test the candidate rather than assume its success.

## 9. Research question and independent variable

Question: under the fixed pool-400/VU200 workload, does changing only the
full-path admission budget from 320 to 352 improve accepted HTTP200 throughput
and controlled-503 rate while preserving safety?

Independent variable: `doeng.admission.max-permits` (or the existing project
property) `320 -> 352`.

## 10. Frozen variables

Full-path mode, zero-wait fail-fast, HTTP pool 400, pending/timeout settings,
CPU 2, memory 3 GiB, DB pool 10, VU200, duration 105 s, one-second pacing,
AI delay 2,000 ms, storage delay 100 ms, client timeout 10 s, same fixture,
auth, payload, DB/storage/completion semantics, fresh JVM, recovered observer,
JFR and continuous snapshots OFF, DB/container monitoring ON, load-stop
snapshot and 30-second drain ON. No retry, fallback, queue, per-stage gate,
pool tuning, scheduler, or workload change is allowed.

## 11. Success criteria and classification

Three VALID AFTER runs are required. Capacity targets are successful HTTP200
throughput median >=124.0172 RPS, controlled 503 median <=37.689%, and accepted
p95 median <=4,263.6 ms. Safety requires HTTP500=0, pool exception=0, permit
leak=0, max in-use<=352, acquired=released after drain, correctness PASS, and
drain<=30 s. Resource/observer/configuration fingerprints must pass.

Classification is A/B/C/D/E/F exactly as frozen in the supplied design. An
invalid run is replaced once for the same arm/contract; a poor system outcome
is never invalidated.

## 12. Minimum run plan

Source/config audit -> tests/build -> preflight -> one diagnostic scout ->
three VALID full-path-352 AFTER runs -> aggregate -> classification -> hard
stop. No automatic MVC comparison or further permit candidate is authorized.

## 13. Tuned MVC comparison gate

Only classification A, with the safety gate fully passing and the 352 source
fingerprint fixed, may open a separately designed comparison against the MVC400
reference. Results B-F do not authorize that comparison.

## 14. Claim boundary

Allowed after a successful run: evidence about this fixed synthetic workload,
this full-path admission budget, and the observed safety/capacity outcome.

Forbidden: claiming 352 is optimal, claiming production capacity, claiming
WebFlux superiority over MVC, or inferring causality from the single heuristic
calculation.

## 15. Expected changes and hard stop

If approved, only the existing full-path permit value, its run configuration,
experiment scripts/artifacts, and result/ledger documents may change. No
production behavior redesign is part of this design. This document is the
preregistration and requires explicit user approval before implementation or
execution.
