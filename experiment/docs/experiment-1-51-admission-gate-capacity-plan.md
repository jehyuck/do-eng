# Experiment 1-51 — Capacity Rebalance + Full-Path Admission Gate

## Objective

Determine whether two independent changes improve successful completion under the frozen high-load protocol:

1. Rebalance isolated provider pools from `50 / 400 / 50` to `100 / 400 / 100`.
2. With the rebalanced pools fixed, enable the existing whole-request admission gate before the token -> AI -> storage -> DB chain.

This experiment does not claim that a gate increases theoretical downstream capacity. It tests whether limiting logical in-flight work prevents avoidable connection pending, timeout, cancellation, and cleanup overhead from reducing effective successful throughput.

## Frozen implementation basis

- Base commit: `787ce5cc9a494da3f2e62bd15f7e14951033f4cc`
- Branch: `experiment/exp151-admission-gate-capacity`
- Existing gate implementation: `AiOutboundAdmissionGate`
- Admission scope: `FULL_PATH`
- Gate behavior in the enforced cell: fail-fast `ENFORCE`, limit `400`
- No production business-flow code change is permitted.
- No TOKEN -> AI -> STORAGE -> DB ordering change is permitted.

## Cells

### Cell A — Capacity rebalanced, gate OFF

Override:

`experiment/compose/experiment-1-51-capacity-100-400-100-gate-off.override.yml`

- TOKEN active/pending: `100 / 160`
- AI active/pending: `400 / 640`
- STORAGE active/pending: `100 / 160`
- Total isolated active budget: `600`
- Admission mode: `OFF`

Purpose: determine whether the prior `50 / 400 / 50` allocation itself caused avoidable TOKEN/STORAGE pressure.

### Cell B — Same capacity, gate ENFORCE

Override:

`experiment/compose/experiment-1-51-capacity-100-400-100-gate-on.override.yml`

- Provider budgets identical to Cell A
- Admission mode: `ENFORCE`
- Admission scope: `FULL_PATH`
- Max concurrent whole requests: `400`

Purpose: determine whether preventing more than 400 requests from entering the full outbound chain reduces internal pending, timeout, cancellation, and transport failure while improving effective successful throughput.

## Execution order

Run both observation modes for each cell using the same frozen workload and environment as Exp150:

1. A-D: Cell A, diagnostic observation ON
2. A-P: Cell A, performance observation OFF
3. B-D: Cell B, diagnostic observation ON
4. B-P: Cell B, performance observation OFF

Do not compare across cells unless all of the following match:

- Git commit and built JAR
- Docker Compose base file
- application/mock/DB CPU and memory limits
- fixture bytes and SHA-256
- actor/token set
- arrival mode, duration, interval, timeout
- AI delay/status and storage delay/status
- DB seed and row counts
- warm-up protocol

## Required validations before load

For every cell:

- Application health is `UP`.
- Pool mode is `ISOLATED`.
- Provider meters expose the expected active and pending budgets.
- Cell A reports admission `OFF`.
- Cell B reports admission `ENFORCE`, scope `FULL_PATH`, configured limit `400`.
- Existing L1-L4 regression and production-source gates remain PASS.

Abort the cell if any runtime value differs from the declared configuration.

## Required evidence

Capture the existing Exp150 evidence plus:

### Admission

- configured mode, scope, and limit
- started
- completed
- rejected
- cancelled
- released
- current in-use
- max observed in-use
- permit leak
- would-reject

### Provider pools

For TOKEN, AI, STORAGE separately:

- max connections
- active peak
- pending peak
- pending-acquire timeout/error count where available

### Client outcome

- attempts
- HTTP 200
- HTTP 500
- HTTP 503 separately
- client timeout
- connection/transport errors by category
- successful RPS
- success rate
- latency p50/p95/p99
- max in-flight

### Application/runtime

- application CPU average/peak
- memory average/peak
- GC count and pause time where available
- event-loop delay
- restart/OOM
- stage p50/p95/p99 and failure counts
- DB/R2DBC pending and integrity checks

## Primary comparisons

### Capacity effect

Compare Exp150 `50 / 400 / 50, gate OFF` against Cell A.

A capacity-rebalance benefit requires directional improvement in:

- TOKEN and STORAGE pending peaks
- successful RPS or success rate
- timeout/cancellation/transport error

without introducing DB integrity failure, OOM, restart, or uncontrolled CPU saturation.

### Gate effect

Compare Cell A against Cell B only.

A gate benefit is supported when Cell B shows:

- lower provider pending peaks
- lower client timeout and cancellation
- lower transport error
- lower internal max in-flight
- no permit leak
- equal or higher successful RPS or materially higher success rate

HTTP 503 rejection must be reported separately and must not be counted as successful completion. A result that only converts timeout into 503 is stability protection, not throughput improvement.

## Interpretation rules

- Do not call `600` the optimal pool size from one run.
- Do not call the gate a throughput improvement unless successful RPS increases under the same workload.
- Do not hide rejected requests inside generic HTTP 500 counts.
- Do not extend client timeout for only one cell.
- Do not claim backpressure. This is whole-request admission control before outbound subscription.
- Do not change production Java code during execution.

## Final classification

Choose one:

- `CAPACITY_REBALANCE_BENEFIT_CONFIRMED`
- `CAPACITY_REBALANCE_NO_BENEFIT`
- `GATE_EFFECTIVE_THROUGHPUT_BENEFIT`
- `GATE_STABILITY_ONLY`
- `GATE_NO_BENEFIT`
- `INCONCLUSIVE`

The report must state capacity and gate findings separately.
