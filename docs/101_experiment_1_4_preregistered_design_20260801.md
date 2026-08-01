# DoEng Experiment 1-4 — Resource-Aligned Outbound Admission Design

Status: DESIGN ONLY / awaiting user approval

This document preregisters the next experiment. No source, test, harness,
image, runtime or Git change is made by this design task.

## 1. Design decision

**PROCEED AFTER ACCOUNTING GATE.**

The mechanism question is well-defined, but execution must not begin until the
runner emits the required request accounting fields and accepted-only latency.
Existing 1-3 raw is retained as contextual BEFORE evidence; it is not silently
discarded or relabeled.

## 2. Experiment name

`Resource-Aligned Outbound Admission Validation`

## 3. Research question

At fixed pool400/VU200/2CPU/3GiB conditions, does replacing one permit held for
the complete token→AI→storage→DB publisher with a shared non-blocking permit
held only around each actual outbound WebClient call preserve the safety gate
while increasing HTTP200 successful throughput and reducing controlled 503s?

This is not a WebFlux-versus-MVC experiment and does not claim framework
superiority.

## 4. Hypothesis

The full-path gate keeps a permit during Base64, storage completion and DB work,
although those intervals do not occupy the shared HTTP connection. Releasing at
the terminal signal of each actual token, AI and HTTP-storage WebClient call
should make the same aggregate budget reusable while keeping the pool below its
400-connection ceiling.

The hypothesis is rejected if safety regresses, or if successful throughput and
controlled-rejection rate do not materially improve after accounting correction.

## 5. Experiment 1-3 accounting audit

Measurement duration is 105 seconds. The existing `throughputRequestsPerSecond`
field equals completed classified requests divided by that 105-second window;
it is not successful throughput.

| Run | Scheduled / completed | HTTP200 | HTTP503 | Uncontrolled | Successful RPS | Completed RPS | Existing RPS meaning |
|---|---:|---:|---:|---:|---:|---:|---|
| CORE-001 | 769 / 769 | 451 | 318 | 0 | 4.295 | 7.324 | all completed classified requests / 105 s |
| CORE-002 | 705 / 705 | 430 | 275 | 0 | 4.095 | 6.714 | all completed classified requests / 105 s |
| CORE-003 | 697 / 697 | 419 | 278 | 0 | 3.990 | 6.638 | all completed classified requests / 105 s |

The existing artifacts do not separately emit:

- started requests (only scheduled/completed and unfinished)
- accepted-only p95/p99
- per-run admission acquired/rejected/released counters
- application stage counts for the core runs
- an explicit request-generation-suppression/early-stop counter

The load scenario stopped each user after a successful response. This means the
offered request stream was not constant for the full 105 seconds. Therefore
1-3 raw can be reused for safety/context, but a clean capacity comparison must
rerun a corrected accounting contract before 1-4 aggregation.

## 6. Current permit lifecycle

Current Experiment 1-3 code holds one permit around the complete publisher:

```text
acquire
  → token WebClient call
  → AI WebClient call
  → Base64 decode
  → HTTP storage WebClient call
  → DB/R2DBC completion
  → response completion
release on complete/error/cancel
```

The CAS gate is non-blocking and fail-fast. It does not use a Java semaphore,
`block()`, timed waiting, or a blocking queue. Tests cover error/cancel release.

## 7. Proposed permit lifecycle

The outer request-level gate is removed. The same aggregate gate is acquired
inside each lazy outbound publisher immediately before the corresponding
WebClient subscription and released on the call's terminal signal:

```text
request
  → acquire token permit → token WebClient response decode → release
  → acquire AI permit → AI WebClient response decode → release
  → Base64 decode (no HTTP permit)
  → acquire storage permit → storage WebClient response decode → release
  → DB/R2DBC (no HTTP permit)
  → response completion
```

Acquire must happen at subscription time, not at method construction time.
Every complete/error/cancel path releases exactly once, including cancellation
before connection acquisition and response-codec errors.

## 8. Protected resource

The protected resource is the shared Reactor Netty `doeng-external`
connection-acquisition boundary used by token, AI and HTTP storage. R2DBC pool
capacity is a separate resource and is deliberately outside the HTTP permit.
Base64 and response composition are also outside the HTTP permit.

## 9. Recommended limiter implementation

Use the existing custom CAS-based gate, extended to expose a shared
`executeOutbound(stage, supplier)` operation. Do not add Resilience4j, a
blocking semaphore, a second queue, or a new dependency for this experiment.

Mechanism: one aggregate shared budget; independent per-call acquire/release;
zero-wait fail-fast; stage-tagged counters. The Reactor Netty pending-acquire
queue remains the lower-level safety signal and is not duplicated by an
application wait queue.

## 10. Recommended permit budget

**Recommended outbound permit budget: 320.**

Evidence and calculation:

```text
pool maxConnections = 400
reserved headroom   = 80
recommended budget  = 400 - 80 = 320
```

The value also preserves the 1-3 proven no-leak configuration while changing
only holding scope. `400` is rejected because it leaves no room for connection
reuse variance, non-mission management traffic or measurement uncertainty.
No evidence justifies a higher number, so a budget sweep is prohibited.

Limitations: this is a fixed synthetic envelope and not a production capacity
claim. The 80-connection headroom is an explicit safety margin, not a measured
universal constant.

## 11. Independent variable

Only admission holding scope changes:

```text
BEFORE: one permit across the complete request publisher
AFTER:  one shared permit per actual token/AI/storage WebClient call
```

The budget remains 320. Pool, timeout, worker, CPU, memory, DB, retry,
fallback, payload, mock delay and workload remain unchanged.

## 12. Frozen variables

- corrected WebFlux only; MVC is not executed
- pool400 and existing pending/timeout settings
- CPU2, memory3GiB, fresh JVM
- DB pool10
- AI2,000ms, storage100ms
- VU200, duration105s, frame/reconnect1s, client timeout10s
- same fixture/auth/token/DB/storage/completion contract
- JFR/NMT/comprehensive snapshots/mock continuous polling OFF
- DB/container monitor, load-stop snapshot, drain and consistency ON
- admission budget320 and zero-wait policy

## 13. BEFORE evidence decision

**RERUN REQUIRED for capacity comparison; REUSE for safety/context.**

The 1-3 raw runs are valid evidence that the full-path gate prevented
uncontrolled pool failures. They cannot alone support a precise capacity delta
because successful throughput and accepted latency are not separately emitted,
and the load driver early-stops users after success. A corrected accounting
contract must produce a replacement BEFORE cohort before comparing AFTER.

## 14. Success and failure criteria

Safety gate for every VALID AFTER run:

- `PoolAcquirePendingLimitException = 0`
- uncontrolled HTTP500 = 0
- permit leak = 0
- configured permit limit exceeded = 0
- controlled 503 has no DB/storage side effect
- correctness PASS
- drain completes within 30 seconds

Capacity comparison uses, in order:

1. HTTP200 successful throughput
2. controlled 503 rate among classified requests
3. accepted-only p50/p95/p99
4. completed classified throughput
5. permit utilization and pool active/pending

High total RPS caused by fast 503 rejection is not a capacity gain.

## 15. Result classification

- **A — SAFETY PRESERVED, USABLE CAPACITY IMPROVED:** all safety gates pass,
  HTTP200 throughput increases materially and controlled 503 rate decreases.
- **B — SAFETY PRESERVED, NO MATERIAL CAPACITY GAIN:** safety passes but the
  capacity metrics do not improve materially.
- **C — CAPACITY IMPROVED BUT SAFETY REGRESSED:** HTTP200 improves but any
  uncontrolled 500/pool exception/leak appears.
- **D — CONTROL INSUFFICIENT OR NEW BOTTLENECK:** prior failure remains or a
  new direct bottleneck dominates.
- **E — VARIABLE / INCONCLUSIVE:** valid runs contradict without a resolved
  measurement explanation.

Material improvement must be preregistered numerically in the execution prompt
after the corrected BEFORE accounting is available; it must not be chosen after
seeing AFTER results.

## 16. Minimum run plan

1. Correct and validate the accounting contract (no workload/resource change).
2. Produce corrected BEFORE runs using the unchanged full-path gate.
3. Run one WebFlux diagnostic scout with stage/permit/pool correlation.
4. Apply only the per-outbound-call holding-scope change.
5. Run three VALID AFTER core runs. Replace only instrumentation-invalid runs.
6. Stop after the preregistered run count; no budget sweep or second remediation.

## 17. Evidence collection contract

Each run must preserve provenance, fixture/config fingerprints, scheduled,
started, completed, HTTP200, controlled503, uncontrolled, timeout, abort and
other outcomes; successful and completed throughput; accepted-only latency;
permit attempted/acquired/rejected/released/current/max/wait/cancel/leak;
stage counts and durations; pool time series; CPU/memory/PIDs; DB pool; mock
in-flight; load-stop/drain; and correctness/no-side-effect checks.

## 18. Test contract

Before load execution, tests must cover token/AI/storage complete/error/cancel
release, sequential per-call permits, aggregate limit, cancellation before and
during WebClient acquisition, rejection mapping, unrelated exception
propagation, DB outside HTTP permit, response-after-storage/DB, controlled503
no-side-effect, feature-off behavior and permit leak zero.

## 19. Reviewer objection matrix

- The application limiter is not a replacement for the Netty pool; it is an
  earlier bounded admission guard with explicit outcome semantics.
- A shared budget is used because all three calls share one provider; no claim
  is made about independently pooled dependencies.
- DB is outside the HTTP permit because it uses the R2DBC pool, a separate
  resource; its active/pending metrics remain observed.
- 320 is retained to isolate holding scope, not presented as an optimal value.
- 503 reduction is evaluated alongside HTTP200 throughput and accepted latency;
  rejection speed alone cannot create a capacity claim.
- Nginx, JWT caching/local validation, pool tuning and MVC are outside scope.

## 20. Claim boundary

Allowed: under this fixed synthetic envelope, compare full-path versus
per-outbound-call admission holding and report safety/capacity outcomes.

Prohibited: universal WebFlux superiority, production capacity limits, claims
about S3/AI realism beyond the mock contract, or claims that 320 is optimal.

## 21. Hard stop

No local JWT, token cache, dependency pool isolation, Nginx change, adaptive
concurrency, pool/pending tuning, worker/resource tuning, Base64 scheduler
change, retry/fallback, VU sweep, MVC rerun or second remediation.

## 22. User decisions required

Approval is needed for:

1. treating 1-3 as safety/context BEFORE but requiring corrected-accounting
   BEFORE runs for capacity comparison;
2. retaining budget 320 and zero-wait fail-fast;
3. accepting the per-outbound-call holding scope as the sole independent
   variable.

## 23. End condition

This design task ends here. No implementation prompt, build, load, commit or
push is produced or executed.
