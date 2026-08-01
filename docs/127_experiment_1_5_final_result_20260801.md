# DoEng Experiment 1-5 Final Result

## Status

Experiment 1-5: **CLOSED**. MVC comparison: **NOT STARTED**.

## Aggregate

| Metric | Full-path 320 BEFORE median | Full-path 352 AFTER median | Target | Pass |
|---|---:|---:|---:|---|
| Successful HTTP200 RPS | 112.7429 | 108.7429 | >=124.0172 | NO |
| Controlled 503 rate | 42.689% | 40.331% | <=37.689% | NO |
| Accepted p95 | 3,876 ms | 5,958 ms | <=4,263.6 ms | NO |

The AFTER medians are based on the three VALID core runs. Run-to-run values
were materially variable, but no run was invalidated for a bad outcome.

## Safety and resource shape

Permit max was 352 and leak was 0 in all runs; acquired equaled released after
drain. Observer, DB/container collection, correctness, and drain passed. There
were no preserved `PoolAcquirePendingLimitException` strings, but run 002 had
two HTTP500 outcomes. Therefore the safety gate is not fully satisfied.

## Classification

**E - NEW BOTTLENECK / CONTROL INSUFFICIENT**.

The single budget increase did not achieve the capacity target, worsened the
accepted-latency median, and did not preserve the HTTP500 safety condition.
The data do not identify a unique downstream root cause; this classification
does not claim that permit 352 itself is the sole cause.

## What was proved

- A full-path budget of 352 can be wired without changing business flow.
- The budget remained bounded and leak-free in three valid runs.
- The frozen observer/accounting/correctness contract remained executable.

## What was not proved

- 352 is optimal or safe production capacity.
- Full-path 352 improves capacity over 320.
- WebFlux is superior to MVC.
- A specific CPU, DB, mock, or pool mechanism caused the HTTP500.

## Hard stop

No additional permit tuning, sweep, VU change, pool/resource change, MVC
comparison, commit, or push was performed or authorized by this result.
