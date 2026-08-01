# Experiment 1-4 Phase 1-R — AFTER Threshold Freeze

The threshold is frozen before any Phase 2 source change.

## Throughput improvement

```text
T_before = 112.7429 successful HTTP200/s
relative MAD = 2.5715 / 112.7429 = 2.280%
required improvement = max(10%, 2 × 2.280%) = 10%
AFTER target >= 124.0172 successful HTTP200/s median
```

## Controlled rejection reduction

```text
R_before = 42.689%
percentage-point MAD = 1.239 pp
required reduction = max(5 pp, 2 × 1.239 pp) = 5 pp
AFTER target <= 37.689% median controlled rejection rate
```

## Accepted p95 guard

```text
AFTER accepted p95 median <= 3,876 ms × 1.10 = 4,263.6 ms
```

## Safety gate

AFTER must preserve: no uncontrolled HTTP500, no pool acquire exception,
permit leak 0, max in-use <= 320, correctness PASS and drain completion.

No AFTER run was executed in Phase 1-R.
