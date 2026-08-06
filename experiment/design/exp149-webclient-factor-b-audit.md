# Exp149 WebClient Shared Pool Contention Audit

## 1. Current outbound architecture

`ExternalHttpClientConfig` creates one shared provider (`doeng-external`) plus three isolated providers (`doeng-token`, `doeng-ai`, `doeng-storage`). Each named WebClient receives both and `selectProvider()` chooses the shared provider when `doeng.external.pool-mode=SHARED`; the default is SHARED. No new provider is created by the proposed experiment.

The REST path in `AiGameController` is:

`request body -> TOKEN WebClient -> AI WebClient -> decode on parallel scheduler -> STORAGE WebClient -> R2DBC transaction (claim -> progress update -> picture insert) -> response`.

`DBComponentHttp` composes this path with `Mono`/`flatMap`; the target REST path does not call `subscribe()` itself. Legacy WebSocket classes and `DBComponent` contain fire-and-forget subscriptions, but they are outside the `/game/face` REST path audited here.

## 2. Shared pool configuration

Source: `backend/doEngGameFlux/src/main/java/com/example/doenggameflux/config/ExternalHttpClientConfig.java` and `ExternalServiceProperties.java`.

- Exp148 runtime: `poolMode=SHARED`, `maxConnections=500`, `pendingAcquireMaxCount=800`, `pendingAcquireTimeout=10000ms`, FIFO, idle/eviction disabled.
- In SHARED mode TOKEN, AI, and STORAGE all select `sharedConnectionProvider`.
- Reactor Netty still keys pools by remote address inside a provider. In Exp148 all three mock endpoints resolve to `experiment-mock:9100`, so the observed 500 active limit is a shared remote-address limit. In production, different host:port values would have separate per-remote pools; 500 is not a global cross-host total.

## 3. Stage occupancy evidence

Exp148 diagnostic stage maxima were TOKEN 849, AI 810, STORAGE 233, with stage p95 durations TOKEN 9514.97ms, AI 9005.81ms, STORAGE 7018.50ms. These are stage-operation in-flight counters, not connection counts; they cannot be converted into exact connection ownership without stage-tagged lease telemetry.

Performance/diagnostic pool summaries both observed active peak 500. Pending peak was 1343 in P and 768 in D. The diagnostic run recorded 498 client connection errors and 3422 timeouts; the performance run recorded 6 connection errors and 2869 timeouts. The direction is evidence of a contention-sensitive path, but not proof that the shared pool alone caused the HTTP 500s.

## 4. Exp148 failure interpretation

- P HTTP 500 (1535): the preserved client artifact classifies them as application HTTP 500, but the package does not contain a complete independent server exception-to-request mapping. Exact root-cause attribution is NOT AVAILABLE.
- D HTTP 500 (197): same limitation; the reduction is accompanied by 498 UNKNOWN_TRANSPORT connection errors and more client timeouts. It must not be interpreted as a pure observation effect.
- No application restart/OOM evidence was found in the preserved summaries. Mock drain reached zero in both runs. Consistency passed in both runs.
- Active=500 coincided with positive pending in both runs, but the pool gauge is not a stage-tagged lease record.

## 5. Cancellation/orphan audit

For `/game/face`, the returned publisher owns the TOKEN, AI, STORAGE, and DB chain, and there is no direct `subscribe()`, `cache`, `share`, `publish`, or `CompletableFuture` bridge in that path. WebClient response bodies are consumed with `bodyToMono`. Therefore cancellation propagation is **CANCELLATION_PROPAGATES for the audited REST path**.

This does not prove every endpoint is free of orphan work: legacy WebSocket handlers and `DBComponent` explicitly subscribe internally. Those paths are outside this experiment and are recorded as a scope limitation, not as a Factor B cause.

## 6. Candidate comparison

| Candidate | Evidence fit | Production change size | Main risk | Decision |
|---|---|---:|---|---|
| Separate TOKEN/AI/STORAGE providers | Directly tests shared-pool contention; provider selection already exists | One configuration switch plus budget-preserving pool values | Total socket count and per-host fairness change | **Selected** |
| Admission/concurrency limit | Could reduce queueing but changes control policy and confounds pool attribution | Larger behavioral change | Reintroduces Factor A/admission confounding | Not selected |
| Pending/timeout tuning | Changes waiting policy, not resource ownership | Configuration-only | Cannot distinguish queue policy from pool contention | Not selected |
| Pool size increase | Already explored in prior experiments | Configuration-only | Does not test shared ownership | Not selected |

## 7. Selected Factor B

Selected intervention: switch `DOENG_EXTERNAL_POOL_MODE` from `SHARED` to `ISOLATED`, using the already implemented `selectProvider()` path. No production Java change is required for the first test. The initial budget-preserving candidate is:

- TOKEN: max 50, pending 80
- AI: max 400, pending 640
- STORAGE: max 50, pending 80
- active total: 500; pending total: 800

These are preregistered diagnostic values, not claimed optimal values. They preserve the Exp148 total budget while preventing the slow AI stage from consuming the same remote-address pool leases as TOKEN/STORAGE.

## 8. Exact implementation design

Expected overlay-only change:

- New file: `experiment/compose/experiment-1-49-factor-b-isolated.override.yml`
- `DOENG_EXTERNAL_POOL_MODE=ISOLATED`
- `DOENG_TOKEN_POOL_MAX_CONNECTIONS=50`
- `DOENG_TOKEN_POOL_PENDING_MAX_COUNT=80`
- `DOENG_AI_POOL_MAX_CONNECTIONS=400`
- `DOENG_AI_POOL_PENDING_MAX_COUNT=640`
- `DOENG_STORAGE_POOL_MAX_CONNECTIONS=50`
- `DOENG_STORAGE_POOL_PENDING_MAX_COUNT=80`
- Preserve pool observation, timeouts, workload, mock delay, resources, DB pool, and admission OFF.

The production source remains unchanged. If the existing isolated-budget validation rejects these values, stop before load and report the configuration mismatch; do not tune around it.

## 9. Focused tests

Before any load:

1. `ExternalHttpClientConfigTest` verifies all named providers/WebClients are created.
2. `ExternalServiceProperties` validation test verifies isolated active/pending sums equal shared 500/800.
3. A configuration smoke must confirm TOKEN/AI/STORAGE WebClients resolve to `doeng-token`, `doeng-ai`, and `doeng-storage` respectively.
4. Existing Exp148 atomicity and StageObservation tests remain unchanged.

## 10. Two-factor execution plan

Each cell has one Performance (P) and one Diagnostic (D) run with the Exp148 workload and resource contract. No pool size, timeout, admission, mock, or R2DBC change is allowed.

Recommended order:

`A0B1-D -> A1B1-D -> A0B0-P -> A1B0-P -> A0B1-P -> A1B1-P -> A1B1-D`

Existing Exp148 A1B0 P/D artifacts may be reused as reference controls, but are not silently merged into a new 2x2 aggregate. The primary Factor B comparison is A1B0 versus A1B1 under the same corrected source and workload.

## 11. Decision and limitations

The current evidence supports selecting separate providers as the most direct single production configuration intervention. It does not prove shared-pool contention is the sole cause of HTTP 500 or transport errors. A successful A1B1 result would support a bounded claim for this synthetic workload only; it would not establish a universally optimal pool allocation.
