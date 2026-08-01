# Experiment 1-3 — WebFlux Reactive Path Characterization & Remediation

Status: PLANNED / source audit first

## Research question

At the frozen pool400 / VU200 / 2 CPU / 3 GiB envelope, which stage or shared
resource boundary explains the current corrected WebFlux HTTP 500s, and can one
directly evidenced implementation defect be corrected without changing the
performance contract?

This is not a new MVC comparison or tuning exercise.

## Objective and hypotheses

Primary objective: distinguish completion/composition, event-loop blocking or
CPU placement, scheduler pressure, and shared outbound-pool interference using
stage-level source and runtime evidence.

Hypotheses are classified only after evidence:

- R1 completion/composition defect
- R2 event-loop blocking
- R3 event-loop CPU starvation
- R4 CPU scheduler saturation
- R5 shared outbound resource interference
- R6 client/provider lifecycle defect
- R7 storage/DB boundary
- R8 no dominant implementation defect

No classification is selected from latency alone.

## Frozen contract

- Corrected WebFlux only; MVC is historical context, not a new arm.
- CPU 2, memory 3 GiB, fresh JVM per core run.
- Shared outbound connection pool max 400; existing pending/timeout settings.
- DB pool 10; AI delay 2,000 ms; storage delay 100 ms.
- VU 200; frame/reconnect 1 s; duration 105 s; client timeout 10 s; drain 30 s.
- Same fixture, auth/token, database, storage, and completion contracts.
- No pool/worker/CPU/memory/VU/retry/fallback/rate-limit/admission tuning during
  diagnosis or validation.

## Phases

1. **Phase A — inventory:** verify latest source, raw artifacts, ledger and
   uncommitted diff. Preserve the current 1-1/1-2 evidence.
2. **Phase B — static audit:** map request-body, token, AI, decode, storage, DB
   and response completion. Record blocking calls, detached subscriptions and
   WebClient/provider identity.
3. **Phase C — diagnostic scout:** use observation-only stage timing/counters,
   targeted pool metrics, raw errors, container/DB monitors and drain. Do not
   use JFR or comprehensive continuous snapshots.
4. **Phase D — remediation selection:** select at most one correction only when
   a direct causal finding exists. Record rejected alternatives.
5. **Phase E/F — controlled validation:** apply that one correction, pass the
   JDK11/Gradle gate, run one diagnostic scout, then three VALID WebFlux core
   runs under the frozen contract. Invalid runs are replaced individually and
   raw artifacts are retained.

## Observation contract

Diagnostic scout may collect stage start/end, duration, thread, outcome,
exception class, stage in-flight, targeted Reactor Netty pool metrics, raw
application logs, container/DB health, load-stop snapshot and drain.

Core validation keeps only low-overhead stage counters/error classification,
container/DB/load-generator health, load-stop snapshot, drain and correctness.
BlockHound, JFR, full successful-request traces and comprehensive polling stay
off unless a separately approved diagnostic is required.

## Validity and decision rules

Instrumentation/provenance/fixture/fresh-JVM/collector/correctness-verifier
failures are INVALID. HTTP 500, timeout, p95, pool pressure, scheduler backlog
and drain failure are SYSTEM OUTCOME, not automatic invalidity.

Three VALID core runs with uncontrolled HTTP500 <= 1%, no
`PoolAcquirePendingLimitException`, no resource/permit leak, drain <= 30 s and
correctness PASS classify as A (reactive path stabilized). Otherwise classify
B/C/D/E according to the evidence, without further tuning or an automatic
second remediation.

## Planned files/results

- `docs/96_experiment_1_3_reactive_path_plan_20260801.md`
- `docs/97_experiment_1_3_source_audit_20260801.md`
- `docs/98_experiment_1_3_diagnostic_result_20260801.md`
- `docs/99_experiment_1_3_final_result_20260801.md`
- `experiment/results/EXP13-*` (raw per-run artifacts)

## User decision points

If Phase C cannot establish a direct causal defect, stop with R8/C rather than
inventing a remediation. No production-capacity claim follows from this plan.
