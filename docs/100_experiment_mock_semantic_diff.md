# Historical vs Current Experiment-Mock Semantic Diff

## 1. Source identity

The two `/app/server.js` files were extracted from Docker images with `docker create` and `docker cp`; neither container was started.

| | Historical RUN-252 | Current SERVICE1S-M001 |
|---|---|---|
| Image | `doeng-capacity-closure-20260731-experiment-mock:latest` | `doeng-service1s-mvc400-experiment-mock:latest` |
| Image ID | `sha256:60f473741f2c3be6da1f07f5069ac2c5c8c3e9e61cac4d8da83d4f8e0a18754a` | `sha256:6fcbe49ab0505f003ff17eaf187e5c813a8cea107a30412b2d4f4e79848546d3` |
| `/app/server.js` SHA-256 | `d3951b3b616062ca160db3ad063362a77b4a4b4fe4dbb70170e5d09c761e3de4` | `a335d8fabdd0210b9ae752d99254340db1639e3ec5b525d0f71d634e19b00286` |
| `/app/server.js` bytes | 11,174 | 16,207 |
| Node runtime in image | 20.20.2 | 20.20.2 |

The extracted hashes match the previously recorded audit values. `SOURCE_HASH_VERIFIED=PASS`.

## 2. Route inventory

The route inventory is unchanged between the extracted historical and current source:

| Route | Historical | Current | Result |
|---|---|---|---|
| `GET /health` | yes | yes | same |
| `GET /api/member/ai` | yes | yes | same |
| `POST /__auth/users` | yes | yes | same |
| `POST /__auth/login` | yes | yes | same |
| `POST /__control` | yes | yes | same |
| `POST /__reset` | yes | yes | same |
| `GET /__requests` | yes | yes | same |
| `GET /__metrics` | yes | yes | same |
| `GET /__storage` | yes | yes | same |
| `PUT /storage/object` | yes | yes | same |
| `POST /analyze/face` | yes | yes | same |
| `POST /analyze/object` | yes | yes | same |
| `POST /analyze/doodle` | yes | yes | same |

The application-requested paths, `/api/member/ai`, `/analyze/face`, and `/storage/object`, therefore have the same route endpoints and methods.

```text
AI_REQUEST_PATH: SAME
STORAGE_REQUEST_PATH: SAME
```

## 3. AI request critical path

Both versions perform the same core sequence for an AI request:

```text
observe request
-> await JSON body parsing
-> snapshot aiState
-> increment aiInFlight / update aiMaxInFlight
-> setTimeout(snapshot.delayMs)
-> status failure response or JSON result response
-> decrement aiInFlight / increment aiCompleted in finally
```

The response body behavior is the same: successful responses contain `result` and, when true, the normalized image payload; error status values return the same mock error shape. Both use `sendJson`, `Content-Type: application/json; charset=utf-8`, computed `Content-Length`, and `response.end`.

The current source adds lifecycle callbacks around this sequence:

- request received;
- request aborted/closed;
- delay started;
- response write started;
- response finished/closed;
- socket accepted/active/inactive/closed/error events.

The current source also adds `closeBeforeResponse`, but the current SERVICE1S mock-control artifact explicitly records `closeBeforeResponse=false`. The option is therefore not active in the audited run.

```text
AI_DELAY_SEMANTICS: SAME
AI_REQUEST_PATH: SAME
```

## 4. Delay semantics

Both historical and current AI handlers take a per-request snapshot and use:

```text
setTimeout(..., Math.max(0, snapshot.delayMs))
```

The storage handler uses the same per-request snapshot and the same `setTimeout` form with `snapshot.delayMs`. There is no busy wait, synchronous sleep, shared serialization lock, or explicit semaphore in either extracted source.

The raw run control values are also the same for the audited pair:

```text
AI: result=true, delay=2000ms, status=200
Storage: delay=100ms, status=200
```

Equal configured delay does not mean equal implementation overhead, but the timer/delay mechanism itself is unchanged.

```text
AI_DELAY_SEMANTICS: SAME
STORAGE_SEMANTICS: SAME
```

## 5. Concurrency and lifecycle semantics

The historical source already had request counters, `aiInFlight`, `aiMaxInFlight`, `aiCompleted`, storage counters, `observedRequests`, and global request recording. It already used one independent timer per AI/storage request and did not serialize requests through a global queue.

The current source adds:

```text
aiLifecycleEvents = []
socketIds = new WeakMap()
socketMetadata = new WeakMap()
```

and appends event objects through `observeAiLifecycle` and `observeConnection`. This is not a concurrency cap or a request admission limit. It is additional per-event object construction and array append work on the AI request path, plus per-connection event work.

Classification:

```text
Current lifecycle instrumentation:
POTENTIALLY_SCALING_CRITICAL_PATH_OVERHEAD
```

The current `/__metrics` path returns `aiLifecycleEventCount`, and `/__requests` returns the accumulated lifecycle array. The event array is reset only by the existing reset path; it is not bounded by a ring buffer or periodically compacted.

```text
POTENTIAL_ACCUMULATION_COST: YES
```

This identifies a plausible scaling difference, not a measured causal attribution for the MVC result.

## 6. Strict authentication

The historical and current token behavior is structurally the same:

- registration is stored in a `Map`;
- login creates mock-issued tokens and stores them in a `Map`;
- strict mode resolves the Authorization value with `issuedTokens.get(...)`;
- invalid or unregistered values return the same failure behavior;
- reset clears auth maps and counters.

The historical post-run metrics show strict auth enabled with 160 registered/issued users. The current run uses the current strict-auth control, and the source lookup remains O(1) `Map` access. No new per-request full-array auth scan was found.

```text
STRICT_AUTH_OVERHEAD: O1_SMALL
```

No historical/current strict-auth semantic difference was found that explains the large request backlog by itself.

## 7. Storage path

The storage route is unchanged in the extracted diff. Both versions:

1. observe the request;
2. validate the `key` query parameter;
3. read the request body into a buffer;
4. snapshot storage state;
5. increment in-flight counters;
6. use one `setTimeout` for the configured delay;
7. compute object byte count and SHA-256;
8. store the object in the same in-memory `Map`;
9. return the same JSON response and decrement counters in `finally`.

```text
STORAGE_SEMANTICS: SAME
```

The current lifecycle/socket instrumentation is attached to the AI path, not to a changed storage algorithm.

## 8. HTTP response and connection semantics

The `http.createServer` construction, `sendJson` implementation, content headers, body serialization, and response completion behavior are unchanged in the historical/current diff. No changes to `keepAliveTimeout`, `headersTimeout`, `requestTimeout`, server-level max connections, or compression were found.

The current source observes connection events and can destroy the request socket only when the optional `closeBeforeResponse` branch is enabled. The audited current control artifact sets it to false.

```text
HTTP_CONNECTION_SEMANTICS: SAME for the audited run
```

## 9. Environment-variable semantics

Both versions read the same primary environment names for:

```text
MOCK_MEMBER_ID
MOCK_AI_RESULT
MOCK_AI_DELAY_MS
MOCK_AI_STATUS
MOCK_STORAGE_DELAY_MS
MOCK_STORAGE_STATUS
MOCK_PORT
```

The current source adds the optional `closeBeforeResponse` field to AI control-state handling. The current run records it as false. The current compose runtime also enables strict auth and sets the same effective AI/storage values recorded in the historical run.

The environment value difference is therefore an additional control capability, not an active behavior difference in this run.

## 10. Root-cause relevance

```text
SOURCE_HASH_VERIFIED: PASS
AI_DELAY_SEMANTICS: SAME
AI_REQUEST_PATH: SAME
STORAGE_SEMANTICS: SAME
HTTP_CONNECTION_SEMANTICS: SAME
STRICT_AUTH_OVERHEAD: O1_SMALL
POTENTIAL_ACCUMULATION_COST: YES
```

The meaningful static difference is current lifecycle/socket instrumentation and its unbounded event accumulation. It adds work and memory growth to the current AI path, while the historical source did not have that event stream. It does not change the configured 2,000 ms delay, storage 100 ms delay, route contract, auth lookup algorithm, or response body semantics.

```text
MOCK_BEHAVIORAL_DIFFERENCE:
POTENTIAL_SCALING_DIFFERENCE_FOUND

MOCK_CAN_EXPLAIN_LARGE_PERFORMANCE_GAP:
NOT_PROVEN
```

Static code inspection cannot quantify how much of the SERVICE1S MVC backlog or timeout outcome came from this instrumentation. A controlled bridge A/B would be required to promote it from candidate to supported explanation; that experiment was not run here.

## 11. Final report

```text
PERFORMANCE_LOAD_EXECUTED: NO
APPLICATION_STARTED: NO
CODE_CHANGED: NO
CONFIG_CHANGED: NO
```

No workload, application endpoint, or new experiment was executed. Temporary extracted files and diagnostic containers were removed after inspection.
