# Experiment 1-6 - Claim/Evidence Map

| 주장 | 근거 | 범위 | 판정 |
|---|---|---|---|
| AI mock delay was the only changed workload variable | runner source contract, run-config and mock-control artifacts | fixed synthetic workload | CONFIRMED |
| AI latency affected full-path usable capacity | AI1000/AI500 medians vs AI2,000 baseline | this permit-320 workload | SUPPORTED |
| AI1000 met the preregistered meaningful-improvement thresholds | 136.3333 RPS, 30.186% 503, 4,089 ms p95, safety pass | AI1000 core median | CONFIRMED |
| AI500 was strictly better in every quality dimension | throughput/503 improved, but p95 median 4,503 ms vs AI1000 4,089 ms | core medians | NOT SUPPORTED |
| AI dependency is the sole bottleneck | stage/resource/pool evidence | causal claim | NOT PROVEN |
| 500 ms is production-optimal | no production AI and no delay sweep beyond preregistered arms | production | PROHIBITED |
| WebFlux is superior to MVC | MVC was not run in Experiment 1-6 | framework comparison | NOT TESTED |
