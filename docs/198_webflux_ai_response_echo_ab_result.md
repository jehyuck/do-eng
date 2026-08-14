# WebFlux AI Response Image Echo A/B Result

## Scope

This is the fixed-contract WebFlux A/B experiment for the AI mock response
`image` echo. The A condition preserved the response image field;
the B condition omitted it. No production application source, request payload,
fixture, scheduler, pool, timeout, or resource condition was changed.

The six completed raw runs are the approved order:

`A1 → B1 → B2 → A2 → A3 → B3`

## Provenance and execution validity

All six runs recorded the same run-time Git head:

`56727aefea341b9d907d72d135fa42739bcb2e7f`

The fixture was `image/arc.jpg`, 265745 bytes, SHA-256
`1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`.
Each run used fresh containers and a fresh Compose project, passed the
management-health readiness gate, recorded JFR, completed accounting, and
drained the mock backlog. All six have `executionValidity=VALID` and
`jfr-validation.valid=true`.

The first caller returned a 120-second timeout while A1 was still being
processed. The detached execution subsequently finalized A1 and continued the
approved cohort. This caller observation is retained as harness evidence; it
does not alter the raw run result and no additional A/B workload was started
after the six-run cohort was complete. The later A1 retry slot was therefore
not executed.

## Frozen contract

- Active missions: 160
- Scenario: `reconnect-ramp`; arrival: `staggered`
- Initial users: 160; activation step: 1; activation interval: 3000 ms
- Reconnect delay: 1000 ms; frame interval: 3000 ms
- Duration: 105000 ms; request timeout: 10000 ms
- AI: `true`, HTTP 200, 2000 ms
- Storage: HTTP 200, 100 ms
- Application: 2 CPU, 3 GiB
- HTTP max/pending: 400/400; DB pool: 10
- JVM: Xms 512m, Xmx 2048m

## Run results

| Run | Condition | Echo | Execution | Application outcome | Started | Completed | Success | Timeout | Connection error | Success rate | Successful RPS | p50 | p95 | p99 | Max | Max in-flight |
|---|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A1 | A | yes | VALID | PASS | 6044 | 6044 | 4917 | 1116 | 0 | 81.35% | 46.83 | 4283 | 8084 | 9743 | 10015 | 537 |
| B1 | B | no | VALID | FAIL | 5332 | 5332 | 4132 | 1152 | 0 | 77.49% | 39.35 | 2271 | 7460 | 9422 | 9994 | 538 |
| B2 | B | no | VALID | PASS | 5833 | 5833 | 3448 | 2116 | 184 | 59.11% | 32.84 | 5389 | 9592 | 9901 | 10009 | 544 |
| A2 | A | yes | VALID | PASS | 5669 | 5669 | 4314 | 1351 | 0 | 76.10% | 41.09 | 3803 | 8473 | 9427 | 10006 | 540 |
| A3 | A | yes | VALID | PASS | 5852 | 5852 | 4663 | 1185 | 0 | 79.68% | 44.41 | 4536 | 8753 | 9699 | 9996 | 537 |
| B3 | B | no | VALID | PASS | 5360 | 5360 | 5360 | 0 | 0 | 100.00% | 51.05 | 2156 | 5782 | 7123 | 9849 | 398 |

Latency values are milliseconds. Successful RPS is successful requests divided
by the 105-second measurement duration.

## Response-byte evidence

The mock lifecycle recorded the actual serialized AI response byte count:

- A: 354354 bytes, `result` plus echoed image.
- B: 15 bytes, `result` only.

The A/B functional gate also confirmed HTTP 200, `result=true`, identical
storage bytes and fixture SHA, and the expected response-shape difference.

## JFR target evidence

Within the measurement window, the exact Jackson
`UTF8StreamJsonParser._skipString()` execution-sample counts were:

| Run | Condition | Execution samples | `_skipString` samples | Skip share | Skip samples / 1000 AI completed |
|---|---|---:|---:|---:|---:|
| A1 | A | 3334 | 101 | 3.03% | 16.73 |
| B1 | B | 3098 | 0 | 0.00% | 0.00 |
| B2 | B | 2742 | 0 | 0.00% | 0.00 |
| A2 | A | 3370 | 82 | 2.43% | 15.01 |
| A3 | A | 3507 | 133 | 3.79% | 23.01 |
| B3 | B | 2350 | 0 | 0.00% | 0.00 |

The target cost was lower in B in all three paired comparisons. This is a
sampled execution-sample observation, not a total allocation-byte measurement.

## Pair comparison

| Pair | A run | B run | Skip-cost result | Successful RPS result | p95 result | Success-rate result |
|---|---|---|---|---|---|---|
| 1 | A1 | B1 | B lower | B lower | B lower | B lower |
| 2 | A2 | B2 | B lower | B lower | B higher | B lower |
| 3 | A3 | B3 | B lower | B higher | B lower | B higher |

## Cohort medians

| Metric | A median | B median |
|---|---:|---:|
| Skip share | 3.03% | 0.00% |
| Skip samples / 1000 AI completed | 16.73 | 0.00 |
| Success rate | 79.68% | 77.49% |
| Successful RPS | 44.41 | 39.35 |
| p95 latency | 8473 ms | 7460 ms |

## Classification

`TARGET_COST_REDUCED_NO_SERVICE_GAIN`

Functional equivalence passed and the target `_skipString` cost decreased in
all three pairs. A repeated service-level improvement was not established:
the B condition was better on some service metrics in pairs 1 and 3, but worse
on successful RPS and success rate in pair 2 and on several metrics in pair 1.

## Confirmed

- Removing the mock AI response image changed the serialized response from
  354354 bytes to 15 bytes.
- The response-side Jackson `_skipString` sampled cost was eliminated in all
  three B runs under this contract.
- The six runs were execution-valid and used the same frozen contract.
- A repeated service-level gain was not demonstrated by this six-run cohort.

## Not established

- This does not identify Base64, Jackson, payload handling, WebFlux, or any
  single component as the cause of MVC behavior.
- This does not establish a universal framework advantage or a production
  response-contract change recommendation.
- The sampled JFR cost is not a measurement of total heap allocation bytes.

## Claim boundary

Allowed: under this fixed WebFlux request flow and mock contract, removing the
unused AI response image reduced the targeted response-side Jackson sampled
cost, but did not produce a repeated service-level improvement across the
three pairs.

Prohibited: claiming that the image echo is the sole cause of MVC collapse,
that the change universally improves service performance, or that production
FastAPI response semantics should be changed without a separate decision.

## Evidence locations

The raw run directories are local evidence under
`experiment/results/WEBFLUX-IMAGE-ECHO-{A1,B1,B2,A2,A3,B3}/` and are indexed by
`experiment/config/image-response-echo-ab-evidence-manifest.json`. Large JFR,
log, JSONL, and request artifacts remain outside Git-tracked documentation.
