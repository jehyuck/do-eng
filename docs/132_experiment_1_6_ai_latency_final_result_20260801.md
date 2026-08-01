# DoEng Experiment 1-6 - Final Result

## Status

- Experiment 1-3: PRESERVED
- Experiment 1-4 Phase 1-R: PRESERVED
- Experiment 1-4 Phase 2: PRESERVED (`E`)
- Experiment 1-5: PRESERVED (`E`)
- Experiment 1-6: **CLOSED**
- MVC comparison: NOT STARTED

## Aggregate

| 지표 | AI2,000 baseline | AI1,000 | AI500 |
|---|---:|---:|---:|
| Successful RPS median | 112.7429 | 136.3333 | 137.4762 |
| Controlled 503 median | 42.689% | 30.186% | 29.862% |
| Accepted p95 median | 3,876 ms | 4,089 ms | 4,503 ms |
| AI stage mean median | NOT AVAILABLE | 1,366.7 ms | 1,045.1 ms |
| Pool max active | 320 | 320 | 321 |
| Pool max pending observed median | 12 | 13 | 18 |

AI1000 cleared the preregistered meaningful-improvement thresholds and all
safety gates. AI500 improved throughput and controlled 503 further, and its AI
stage mean was lower, but its accepted p95 median was worse than AI1000. Thus
the complete monotonic sensitivity condition was not satisfied.

## Result classification

**B - PARTIAL AI LATENCY EFFECT**

The experiment supports that synthetic AI service time is a capacity driver in
this fixed full-path workload. It does not support the stronger claim that AI
latency alone determines capacity: tail latency did not improve monotonically,
and resource/pool measurements do not identify a sole causal bottleneck.

## Safety

All six core runs were VALID. HTTP500 was zero in all core runs; pool exception
text was absent; permit max stayed at or below 320; leak was zero; acquired
matched released after drain; correctness, observer, and drain passed. Timeout
counts remained system outcomes.

## What was proved

- Reducing the synthetic AI delay from 2,000 ms to 1,000 ms improved this
  workload's successful throughput and controlled rejection enough to clear
  the preregistered threshold.
- Reducing to 500 ms produced a small further throughput/rejection improvement
  and reduced measured AI-stage mean duration.
- The response-time sensitivity is measurable under the frozen admission and
  pool contract.

## What was not proved

- Production AI latency or production capacity.
- 500 ms as an optimal value.
- AI as the sole bottleneck.
- WebFlux superiority over MVC.

## Hard stop

No 250 ms arm, other delay, permit change, pool change, VU change, timeout
change, application optimization, MVC comparison, PR, merge, or tag was
performed or authorized.
