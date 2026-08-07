# Exp154 Image Decode Scheduler Measurement Result

## Environment

- Source commit: `61a5f73b2f6e5dd8f96d9d5162239d672cd27481`
- Execution: Dockerized Gradle 7.6.1 / OpenJDK 11.0.19
- OS: Linux container
- Available processors: 16
- Max heap: 512 MiB
- Production Java change: none

## Fixture

- Path: `image/arc.jpg`
- Bytes: `265745`
- Base64 length: `354328`
- Data URL length: `354351`
- SHA-256: `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`

## Method

The test-only `ImageDecodeSchedulerProbeTest` decodes the same JPEG data URL through `ImagePayloadDecoder`.

- Cell A: shared `Schedulers.parallel()`
- Cell B: `Schedulers.newParallel("exp154-decode", availableProcessors)`; disposed after each B run
- Concurrency: 1, 2, 4, 8
- Warm-up: 3 batches per concurrency
- Measured: 10 batches per concurrency; each batch contains `concurrency` operations
- Measurement: `System.nanoTime()` around decode, with thread name, decoded byte count and SHA-256
- Execution order: A1, B1, B2, A2, A3, B3

## Run Validity

All six runs are valid. Every measured operation returned the expected 265745 bytes and expected SHA-256; no decode failure occurred.

## Raw Summary

Artifacts:

- `experiment/results/experiment-1-54/environment.json`
- `experiment/results/experiment-1-54/fixture-fingerprint.json`
- `experiment/results/experiment-1-54/raw-measurements.csv` (900 measured operations plus header)
- `experiment/results/experiment-1-54/run-summary.json`
- `experiment/results/experiment-1-54/comparison.md`

## Cell A

Shared parallel p95 values by run (nanoseconds):

| Concurrency | A1 | A2 | A3 | Run median |
|---:|---:|---:|---:|---:|
| 1 | 2,323,616 | 361,542 | 326,564 | 361,542 |
| 2 | 2,285,137 | 10,915,696 | 314,362 | 2,285,137 |
| 4 | 2,132,360 | 333,807 | 328,047 | 333,807 |
| 8 | 2,294,095 | 4,106,719 | 690,751 | 2,294,095 |

## Cell B

Dedicated scheduler p95 values by run (nanoseconds):

| Concurrency | B1 | B2 | B3 | Run median |
|---:|---:|---:|---:|---:|
| 1 | 514,551 | 785,242 | 308,595 | 514,551 |
| 2 | 7,184,456 | 717,603 | 8,627,139 | 7,184,456 |
| 4 | 1,424,769 | 774,357 | 297,796 | 774,357 |
| 8 | 1,331,253 | 568,312 | 9,046,039 | 1,331,253 |

## Comparison

At concurrency 1 and 4, Cell B often has lower individual p95 values. At concurrency 2 and 8, Cell B contains large tail values in B1 or B3. Cell A also has large run-to-run variation, especially A2 at concurrency 2. The direction is therefore not repeated consistently across all runs and concurrency levels.

## Noise and Limitations

- This is a test-only decode probe, not an HTTP or end-to-end WebFlux benchmark.
- It does not measure heap allocation, GC, scheduler queue wait, CPU utilization, or production response latency.
- The Dockerized host and JVM environment differ from the production container environment used by Exp153.
- No statistical significance test was preregistered or performed.

## Decision

`INCONCLUSIVE`

The probe confirms the decode boundary and checksum correctness, but does not provide a stable, repeated advantage for a dedicated scheduler over the shared parallel scheduler. No production scheduler change is authorized by this result.

## Claim Boundary

Allowed: the current decode call is measurable in a test-only path, uses a shared `Schedulers.parallel()` boundary in production, and a dedicated scheduler can be compared without changing production code.

Not established: end-to-end latency improvement, CPU or GC improvement, memory reduction, operational stability improvement, or superiority of either scheduler.

## Canonical State

```text
EXP153_EVIDENCE:
COMPLETED

EXP153_DECISION:
NO_CLEAR_BENEFIT

EXP154_PROBE:
COMPLETED

EXP154_DECISION:
INCONCLUSIVE

EXP154_PRODUCTION_JAVA_CHANGE:
NONE
```
