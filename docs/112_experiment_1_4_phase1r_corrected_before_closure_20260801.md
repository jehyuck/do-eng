# Experiment 1-4 Phase 1-R — Corrected BEFORE Closure

## Frozen configuration

WebFlux corrected full-path admission; budget 320; zero-wait controlled 503;
VU200; 105 seconds; one-second pacing; AI 2,000 ms; storage 100 ms; client
timeout 10 seconds; HTTP pool 400; DB pool 10; application 2 CPU/3 GiB; fresh
JVM; same fixture/auth/DB/storage/completion contract; JFR and continuous
snapshots OFF; DB/container monitor ON; load-stop and 30-second drain ON.

## Aggregate

- Successful HTTP200 throughput: median **112.7429 RPS**, min 110.1714,
  max 120.7619, MAD 2.5715.
- Controlled 503 rate: median **42.689%**, min 38.625%, max 43.928%,
  percentage-point MAD 1.239 pp.
- Completed classified throughput: approximately 196.53–196.76 RPS.
- Accepted latency p95: median **3,876 ms**, range 3,162–5,160 ms.
- Accepted p50 values: 2,542 / 2,370 / 2,669 ms.

## Safety and consistency

- Uncontrolled HTTP500: 0, 0, 0 respectively; the first run had one client
  timeout, retained as a system outcome.
- Admission max in-use: 320 in all runs.
- Admission permit leak: 0 in all runs.
- Acquired = released at final snapshot in all runs.
- Drain completed and final mock in-flight returned to zero in all runs.
- DB/storage consistency passed in all runs.
- Pool exception text was not present in preserved core artifacts.

These are observations of this fixed WebFlux corrected configuration, not a
MVC comparison or a general production-capacity claim.
