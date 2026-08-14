# WebFlux AI Response Image Echo A/B Plan

## 1. Purpose

Test one controlled question: when the unused AI response `image` echo is
removed from the experiment mock response, does response-side JSON parsing/
skip work decrease and does the same WebFlux service path show a repeated
service-level improvement under the frozen contract?

This plan does not change the production FastAPI response contract or the
production WebFlux/MVC source.

## 2. Source identity

- Repository: `jehyuck/do-eng`
- Canonical branch: `experiment/webflux-runtime-evidence-handoff`
- Experiment branch: `experiment/image-response-echo-ab-20260814`
- Frozen application source identity: `407e380f0fdb91a167685ebc8300b544039b3d75`
- Current canonical branch at plan time: `3619879b3b6f731d2bb253520c9b198053bb8aeb`
- Prior payload verdict: `docs/196_webflux_image_payload_verdict_closure.md`

## 3. Candidate change

Only `backend/experiment-mock/server.js` response construction is varied via a
mock-only control:

- A / baseline: `echoImage=true`; successful AI response contains `result`
  and normalized `image`.
- B / candidate: `echoImage=false`; successful AI response contains `result`
  and omits `image`.

The default remains `echoImage=true` so historical experiment behavior is
unchanged when the control is absent.

No production FastAPI, WebFlux, MVC, request representation, codec, pool,
timeout, scheduler, fixture, AI delay, storage delay, resource, or validator
change is allowed.

## 4. Frozen contract

- Implementation: corrected WebFlux
- Active users: 160
- Scenario: `reconnect-ramp`
- Arrival: `staggered`
- Initial active users: 160
- Activation step: 1
- Activation interval: 3000ms
- Reconnect delay: 1000ms
- Frame interval: 3000ms
- Duration: 105000ms
- Request timeout: 10000ms
- AI result/status/delay: `true` / 200 / 2000ms
- Storage status/delay: 200 / 100ms
- Application: 2 CPU / 3 GiB
- HTTP pool: max 400, pending 400
- DB pool: 10
- JVM: Xms 512m, Xmx 2048m
- Fixture: `image/arc.jpg`, 265745 bytes,
  SHA256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- JFR: enabled

## 5. Runs and order

Six valid runs are required, three per condition, in this fixed order:

`A1 → B1 → B2 → A2 → A3 → B3`

Each run uses a fresh compose project, fresh application/mock containers,
fresh prepared users, pre-run mock idle gate, source/runtime identity capture,
JFR capture, accounting validation, and post-load drain.

Invalid setup, contract, accounting, or artifact runs are not included in the
six valid-run cohort and are not silently replaced. A result-driven rerun or
additional condition is prohibited.

## 6. Functional equivalence gate

Before any measurement, one harmless request per condition must prove:

- HTTP 200
- `result=true`
- A contains an image with the normalized original Base64
- B omits the image field
- storage succeeds
- DB completion succeeds
- stored object bytes and SHA256 are identical between A and B

If either condition fails this gate, measurement stops and the run is not
started.

## 7. Metrics

Primary target:

- response-side Jackson skip-family `ExecutionSample` count and share
- normalized skip samples per 1000 AI completions

Secondary metrics:

- sampled Jackson/TextBuffer and response-decoder allocation weight
- application CPU and GC/heap behavior
- success rate, successful RPS, p50/p95/p99
- timeout and connection-error counts
- maxInFlight, unfinished requests, AI/storage in-flight and drain

Allocation values are sampled event weights, not total heap allocation bytes.

## 8. Classification

`OPTIMIZATION_SUPPORTED` requires functional equivalence, reduced response-side
skip cost in at least 2/3 pairs, repeated improvement in at least one service
metric, no material correctness regression, and no contradictory core metric.

`TARGET_COST_REDUCED_NO_SERVICE_GAIN` means the target cost decreases in at
least 2/3 pairs but service-level gain is not repeated.

`NO_TARGET_COST_REDUCTION` means the target cost does not decrease in at least
2/3 pairs.

`INCONCLUSIVE_OR_REGRESSION` covers functional failure, invalid provenance,
invalid accounting/JFR, regression, or incomparable pairs.

## 9. Prohibited claims

This experiment cannot establish that Base64, Jackson, payload handling, or
WebFlux is the sole cause of MVC collapse. It cannot establish universal
framework superiority or an optimization benefit outside this frozen contract.
It cannot justify changing the production FastAPI response contract without a
separate human decision.

## 10. Persistence

Small plans, manifests, hashes, and result summaries belong in Git. Large JFR,
logs, and complete raw run packages belong in the evidence package and are
referenced by manifest and SHA256. Raw results are never rewritten to make a
pair valid.

## 11. Approval gate

The plan commit and mock-only functional smoke must pass before any A/B
measurement workload begins.
