# do-eng WebFlux/MVC Final Experiment Closure

## Status

The performance experiment program is closed. No additional workload is required by this closure.

```text
PERFORMANCE_EXPERIMENT_STATUS: CLOSED
ADDITIONAL_PERFORMANCE_RUN: NOT_REQUIRED
HISTORICAL_INVESTIGATION: CLOSED_AS_LIMITATION
```

This document summarizes the frozen SERVICE3S baseline and the preregistered external-I/O supplement. It does not claim universal framework superiority or establish a root cause beyond the evidence below.

## Evidence boundary

The comparison used the same frozen request flow, fixture, load contract, application resource contract, storage condition, HTTP settings, DB pool, and MariaDB image within each pair. The 2-second AI condition has three WebFlux/MVC pairs; the 500ms and 1000ms conditions have one pair each.

Primary evidence:

- `experiment/results/SERVICE3S-PAIR002-artifact-index.json`
- `experiment/results/SERVICE3S-PAIR003-artifact-index.json`
- `experiment/results/IO500-PAIR001-artifact-index.json`
- `experiment/results/IO1000-PAIR001-artifact-index.json`
- `experiment/results/SERVICE3S-W001`, `SERVICE3S-M001`
- `experiment/results/SERVICE3S-W002`, `SERVICE3S-M002`
- `experiment/results/SERVICE3S-W003`, `SERVICE3S-M003`
- `experiment/results/IO500-W001`, `IO500-M001`
- `experiment/results/IO1000-W001`, `IO1000-M001`

Evidence commits:

- `8f8d0777658e5354beb0a9ce83aaf7e17997b306`
- `3d1c57763999b6c6e3ac01dbed78ffd95f12e6b9`
- `17e8f887f02d351c2eecb39e086cdcfa70b8944e`
- `c2e6abdafb0a74fbbc436bf459686e6ae8c0ae61`

All ten supplement/baseline arms recorded here had `executionValidity=VALID` and completed drain evidence.

## SERVICE3S frozen AI=2000ms baseline

Values are the three runs per implementation. Median is used for the summary statistic; ranges retain run-to-run variation.

| Metric | WebFlux runs | WebFlux median (range) | MVC400 runs | MVC400 median (range) |
|---|---:|---:|---:|---:|
| Success rate | 99.9812%, 100%, 100% | **100% (99.9812–100%)** | 55.0762%, 79.7149%, 10.1408% | **55.0762% (10.1408–79.7149%)** |
| Successful RPS | 50.638095, 51.457143, 51.647619 | **51.457143 (50.638095–51.647619)** | 28.571429, 41.542857, 5.419048 | **28.571429 (5.419048–41.542857)** |
| Successful HTTP 200 p50 (ms) | 2152, 2148, 2172 | **2152 (2148–2172)** | 2157, 2152, 7112 | **2157 (2152–7112)** |
| Successful HTTP 200 p95 (ms) | 3092, 2597, 7214 | **3092 (2597–7214)** | 8339, 7006, 9842 | **8339 (7006–9842)** |
| Successful HTTP 200 p99 (ms) | 4441, 3958, 8352 | **4441 (3958–8352)** | 9531, 9181, 9962 | **9531 (9181–9962)** |
| maxInFlight | 291, 267, 487 | **291 (267–487)** | 537, 537, 554 | **537 (537–554)** |

Observed baseline direction: all three WebFlux runs had no client timeout and 99.9812–100% success. MVC400 had lower and variable success, with higher timeout exposure and higher median tail latency in this frozen condition.

## External-I/O latency supplement

The supplement changed only `downstream.aiDelayMs` from the 2000ms baseline. Storage remained 100ms and all pair parity gates passed.

| AI delay | WebFlux success rate | MVC success rate | WebFlux successful RPS | MVC successful RPS | WebFlux p95 (ms) | MVC p95 (ms) | WebFlux maxInFlight | MVC maxInFlight | Repetitions |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 500ms | 100% | 100% | 93.666667 | 90.009524 | 813 | 1679 | 136 | 296 | 1 pair |
| 1000ms | 100% | 13.775% | 71.714286 | 7.266667 | 3739 | 9620 | 355 | 599 | 1 pair |
| 2000ms baseline | 100% median | 55.0762% median | 51.457143 median | 28.571429 median | 3092 median | 8339 median | 291 median | 537 median | 3 pairs |

The 500ms and 1000ms rows are single pairs and should not be described as repeated estimates. They are supplemental observations under their registered conditions.

## Confirmed observations

The evidence directly supports these statements:

1. At 500ms AI delay, both implementations recorded 100% success in their single valid pair; MVC400 recorded higher p95/p99 and maxInFlight than WebFlux.
2. At 1000ms AI delay, WebFlux recorded 100% success while MVC400 recorded 13.775% success and 4,776 client timeouts.
3. Across the three 2000ms baseline pairs, WebFlux success was 99.9812–100%; MVC400 success was 10.1408–79.7149%.
4. The 2000ms baseline medians were 51.457143 successful RPS and 3092ms p95 for WebFlux, versus 28.571429 successful RPS and 8339ms p95 for MVC400.
5. These observations are specific to the tested request flow, frozen resources, mock behavior, fixture, and registered conditions.

## Interpretation allowed by the evidence

The results are consistent with the hypothesis that, under this request flow and fixed resource contract, longer external I/O waiting places greater pressure on the blocking MVC implementation than on the reactive WebFlux implementation.

This is an interpretation of the observed implementation difference, not a universal framework claim. The evidence does not by itself establish:

- thread exhaustion as the root cause;
- CPU or memory exhaustion as the root cause;
- a general performance threshold;
- that WebFlux is superior for all HTTP workloads;
- that MVC must fail at 1 second AI delay;
- that these 2026 experiments recreate or amend a 2023 performance result.

## Historical discrepancy closure

Historical MVC VU160 evidence exists, but exact historical workload/source provenance is insufficient for direct comparison with the current frozen runs. Therefore:

```text
HISTORICAL_MVC_RESULT: REAL_EVIDENCE
CURRENT_DIRECT_COMPARABILITY: NOT_ESTABLISHED
FINAL_STATUS: FOUND_BUT_NOT_COMPARABLE
```

The historical investigation did not establish a supported claim of MVC application-semantic difference, a current/mock semantic explanation, or a meaningful MVC runtime-environment difference. The exact historical `mission-load.js` source was not available for provenance-equivalent comparison.

## Claim-evidence matrix

| Claim candidate | Evidence strength | Allowed wording | Forbidden wording |
|---|---|---|---|
| Longer external I/O waiting was associated with better WebFlux outcomes in this frozen comparison | Moderate; three 2000ms pairs plus one pair at 500ms and 1000ms | “Under the tested request flow and fixed resource contract, WebFlux retained higher completion/success outcomes as AI delay increased.” | “WebFlux is always faster/better.” |
| WebFlux 2000ms success | Strong for tested runs; three valid pairs | “WebFlux recorded 99.9812–100% success across the three 2000ms baseline runs.” | “WebFlux cannot fail under 2s AI latency.” |
| MVC400 2000ms outcome | Strong for tested runs; three valid pairs | “MVC400 recorded lower and more variable success, with median successful RPS 28.571429 and p95 8339ms.” | “Tomcat thread exhaustion is proven as the root cause.” |
| AI500 behavior | Limited; one valid pair | “Both implementations recorded 100% success in the AI500 pair; MVC400 had higher p95 and maxInFlight.” | “The 500ms result is a repeated general baseline.” |

## Closure

```text
SERVICE3S_BASELINE: CLOSED
EXTERNAL_IO_SUPPLEMENT: CLOSED
HISTORICAL_DISCREPANCY: FOUND_BUT_NOT_COMPARABLE
ADDITIONAL_PERFORMANCE_RUN: NOT_REQUIRED
```

No additional workload, tuning, historical investigation, source change, runner change, or configuration change is part of this closure.
