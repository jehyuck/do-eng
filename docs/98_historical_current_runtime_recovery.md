# Historical RUN-250/252 Runtime and Workload Recovery

## 1. Investigation scope

No performance workload, application start, source edit, config edit, or compose edit was performed. The investigation used:

- raw artifacts for `RUN-20260731-250`, `RUN-20260731-252`, `SERVICE1S-W001`, and `SERVICE1S-M001`;
- local Docker image/container metadata;
- `git log --all`, `git reflog --all`, and unreachable Git object inspection;
- historical/current JAR extraction from images using `docker create` and `docker cp` only. The created containers were never started and were removed after extraction.

## 2. Historical Docker recovery

The historical application images are still present in the local Docker cache:

| Historical arm | Image tag | Image ID / digest | Created |
|---|---|---|---|
| RUN-250 WebFlux | `doeng-capacity-closure-20260731-flux-corrected:latest` | `sha256:286c1b6f8d507001b302bc8dd2e65a981658e540e5490efbd7ae00f890afe1f0` | 2026-07-29T08:33:15Z |
| RUN-252 MVC400 | `doeng-capacity-closure-20260731-mvc:latest` | `sha256:81f580e585cde6588c71aca72041faeb09b89b87ffc375d473d41f75a959e05e` | 2026-07-29T08:32:48Z |

The exact historical RUN-250/RUN-252 containers are not retained in `docker ps -a`; only the application images remain. Historical `run-config.json` records the compose project `doeng-capacity-closure-20260731`, services `flux-corrected` and `mvc`, and the historical compose SHA-256 values.

## 3. Historical JAR recovery

`/app/app.jar` was extracted from each historical image without starting it.

| Arm | Historical JAR SHA-256 | Bytes |
|---|---|---:|
| RUN-250 WebFlux | `7a4661876355e4bbd5abd28ccbbf6cae49e197571fdba6b5f1afb20cec9f89cf` | 38,751,018 |
| RUN-252 MVC400 | `3e846b8be2f00d63bda6793da7cd2a795c9dda8778ab14f087f0d20da9faed5f` | 22,790,079 |

The current SERVICE1S image cache was checked in the same way:

| Arm | Current SERVICE1S image ID | Current JAR SHA-256 | JAR comparison |
|---|---|---|---|
| WebFlux | `sha256:abd23d7860bd9eccd738ab5224fd8e2ca31d6612f4037e4f343b87e006b81f90` | `a990f7325a63b42b9427053a03c4a8dcf1ebc064ebeab9c9b2ce72504a1f1559` | different |
| MVC400 | `sha256:2dfbff77ea445c0f41e4dcebf47f1beb5d5ca810a24530022549052daf11ce51` | `3e846b8be2f00d63bda6793da7cd2a795c9dda8778ab14f087f0d20da9faed5f` | same |

The historical/current WebFlux JAR entry lists differ by 29 entries (245 vs 274). The historical/current MVC JAR entry lists are identical (156 vs 156). Both current and historical JARs contain `BOOT-INF/classes/application.yml`.

Therefore:

```text
APPLICATION_ARTIFACT_DIFFERENCE:
CONFIRMED for WebFlux; NOT_CONFIRMED for MVC400 (JAR hash and entry list are the same)
```

This does not prove that the historical MVC working tree source was clean; it proves only that the recovered application JAR is byte-identical to the current SERVICE1S MVC JAR.

## 4. Historical mission-load recovery

The historical workload source hash recorded by the run artifact is:

```text
0e4aa35004f9a2da4b39f59147d523f8a7405aac2e56380bfeef4f2284daf218
```

The current `experiment/load/mission-load.js` hash is:

```text
f3a6eb36798a57ce408de85e5420f65273bb5c2684bc02618822c4c78095619b
```

The target historical hash was not found in reachable Git history, all reflogs, or the inspected 718 unreachable blobs (81 size-compatible candidate blobs checked). No historical source text was recovered; no line-level source diff can therefore be made.

```text
HISTORICAL_MISSION_LOAD_SOURCE:
NOT_AVAILABLE
```

## 5. Raw request and arrival comparison

Historical `client-results.json` contains request identity, frame, status, body, and latency, but no client-side request start or completion timestamp. It cannot support exact per-user start-interval or client-side first-15-second arrival calculations.

The historical `mock-requests.json` does contain `observedAt` timestamps. Counting only `POST /analyze/face` at the mock gives the following downstream-observation series. These are mock observation times, not client request-start times.

| Run | Client started | Client completed | Client max in-flight | Mock POST window | Mock POST RPS | First 15 mock POST counts by second |
|---|---:|---:|---:|---:|---:|---|
| RUN-250 | 15,492 | 15,492 | 480 | 104.759 s | 147.88 | 190, 161, 130, 109, 170, 165, 132, 156, 147, 148, 149, 160, 138, 137, 164 |
| RUN-252 | 15,351 | 15,351 | 480 | 104.727 s | 146.58 | 182, 172, 115, 144, 163, 159, 128, 157, 161, 151, 160, 160, 94, 129, 161 |

Current client-side `requestStartedAt` is available, so exact first-15-second client starts are measurable:

| Run | Client started | Client-window RPS | Max in-flight | First 15 client starts by second |
|---|---:|---:|---:|---|
| SERVICE1S-W001 | 15,901 | 151.44 | 1,531 | 54, 107, 160, 160, 158, 159, 157, 151, 160, 135, 142, 142, 159, 154, 158 |
| SERVICE1S-M001 | 16,493 | 157.08 | 1,616 | 54, 105, 159, 160, 159, 159, 160, 159, 159, 158, 152, 159, 160, 160, 158 |

Current per-user start intervals, calculated from `client-results.json`, are:

| Run | Users | Median interval | P95 interval | Range |
|---|---:|---:|---:|---:|
| SERVICE1S-W001 | 160 | 1,008 ms | 1,226 ms | 999–2,339 ms |
| SERVICE1S-M001 | 160 | 1,007 ms | 1,020 ms | 999–1,630 ms |

Historical per-user intervals are **not available** because the historical client result format omitted timestamps. The historical `maxInFlight=480` versus current `1,531/1,616` alone cannot distinguish a scheduling change from response-time/backlog accumulation.

```text
WORKLOAD_SCHEDULING_DIFFERENCE:
NOT_PROVEN
```

## 6. Runtime and Compose comparison

Both historical run-configs record:

- VU/active missions: 160;
- `intervalMs=1000`, `activationIntervalMs=3000`, `reconnectDelayMs=1000`;
- `durationMs=105000`, request timeout 10000 ms;
- AI `true`, 2000 ms, HTTP 200;
- storage 100 ms, HTTP 200;
- fixture `image/arc.jpg`, 265,745 bytes, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`.

Historical MVC additionally used the recorded MVC thread-400 compose override and both arms used the HTTP-pool-400 override. Historical drain observation was 30 s. Current SERVICE1S uses the same declared workload/downstream/resource values except drain observation is 15 s, and uses different compose file fingerprints (`a430d90c...` base and `bf3d68...` runtime override versus historical `f858b3...` base plus historical overrides).

The current and historical host captures show the same recorded Windows host CPU model and 32 GB-class host memory, but they are different capture times. No host-level causal difference is proven.

```text
COMPOSE_RUNTIME_DIFFERENCE:
CONFIRMED

HOST_ENVIRONMENT_DIFFERENCE:
NOT_PROVEN
```

The historical environment records Git HEAD `8e856468b36dcb1d7297afc05461af01d6dd6424`, with dirty/untracked comparison inputs. Current SERVICE1S run configs record runtime heads `441682524b3629a661a0971e9d31f3472f74c3ea` (WebFlux) and the same preregistered source family for MVC. Exact historical rendered values for every resource/JVM field are not independently present in the old run-config; contract/default values must not be promoted to runtime proof.

## 7. Observed historical outcomes

The historical results themselves are complete and successful in the recorded request sense:

| Run | HTTP 200 | body `true` | timeout | connection error | p95 | p99 | drain |
|---|---:|---:|---:|---:|---:|---:|---|
| RUN-250 WebFlux | 15,492 | 15,492 | 0 | 0 | 2,488 ms | 2,798 ms | complete, 3,010 ms |
| RUN-252 MVC400 | 15,351 | 15,351 | 0 | 0 | 2,490 ms | 2,883 ms | complete, 3,003 ms |

Current SERVICE1S has higher client starts and much higher reported max in-flight, but this report does not treat that as proof of a single scheduling or application root cause.

## 8. Root-cause candidate classification

```text
WORKLOAD_SCHEDULING_DIFFERENCE:
NOT_PROVEN

APPLICATION_ARTIFACT_DIFFERENCE:
CONFIRMED for WebFlux; MVC JAR SAME

COMPOSE_RUNTIME_DIFFERENCE:
CONFIRMED

HOST_ENVIRONMENT_DIFFERENCE:
NOT_PROVEN
```

The strongest evidence is that the WebFlux application artifact changed (historical/current JAR and entry-list differences), while the MVC JAR recovered from the historical image is byte-identical to the current SERVICE1S MVC JAR. Both arms nevertheless have different historical/current image and Compose provenance, and historical client timestamps/source text are missing. Consequently, the evidence does not support attributing the current max-in-flight discrepancy to the workload scheduler alone or to the application alone.

## 9. Not proven / minimum next evidence

- Historical client-side request start/completion timestamps and per-user interval series.
- Historical `mission-load.js` source text and exact line-level diff.
- Full rendered historical Compose values for CPU, memory, JVM, DB pool, ports, profile, and base images.
- A single causal explanation for the current SERVICE1S max-in-flight increase.

No follow-up workload is proposed by this recovery note.
