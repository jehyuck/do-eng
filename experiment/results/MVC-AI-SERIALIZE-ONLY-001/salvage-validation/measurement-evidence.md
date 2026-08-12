# MVC SERIALIZE_ONLY Salvaged Measurement Evidence

## Run

- Run ID: `MVC-AI-SERIALIZE-ONLY-001`
- Measurement: `SALVAGED_VALID`
- Classification: `STABLE`
- Serialization-only collapse: `NO`
- Serialization path sufficient: `NO`
- Workload was not rerun during salvage; this document only records the preserved run.

## Authoritative raw evidence

The following preserved artifacts are used for the salvage decision:

| Evidence | Artifact |
|---|---|
| Request accounting and latency | `client-results.json` |
| Node lifecycle and exit code | `client-process-contract.json` |
| Accounting validity | `client-accounting-contract.json` |
| Scheduler/frozen condition | `scheduler-contract.json` |
| Application/mock observation | `observer.summary.json`, `observer-contract.json` |
| MVC runtime identity/resources | `runtime-contract.json` |
| Mock runtime identity/resources | `mock-runtime-contract.json` |
| No-AI-network contract | `serialize-only-network-contract.json` |
| Pre-cleanup final container state | `mvc-final-state-contract.json`, `mock-final-state-contract.json` |
| Startup/readiness | `startup-gate.json` |
| Image/source provenance | `serialize-only-image-contract.json` |

## Result

| Metric | Value |
|---|---:|
| Started requests | 8,899 |
| Completed requests | 8,899 |
| Unfinished requests | 0 |
| Successful requests / HTTP 200 | 8,891 |
| Connection errors | 8 |
| Client timeouts | 0 |
| Success rate | 99.9101% |
| p50 | 23 ms |
| p95 | 75 ms |
| p99 | 1,044 ms |
| Max latency | 2,479 ms |
| Max in-flight | 166 |
| Node exit code | 0 |
| Accounting valid | true |

The result summary records `successTriggeredReconnects=8,807` under `reconnect-ramp` with `staggered` arrival and the frozen scheduler values. The observer recorded 38 samples, 38 successful application samples, 38 successful mock samples, zero readiness failures, and zero container-state failures.

## Runtime and no-network evidence

- MVC runtime contract: PASS; image ID `sha256:bc823b95e4fa54faf4e3ec5296265524dc36a68eb2a3c6e15eb194405a5d0879`, 2 CPU, 3 GiB, Tomcat/HTTP/DB settings 400/400/10, JVM `-Xms512m -Xmx2048m`.
- Mock runtime contract: PASS; image ID `sha256:0bbf354a08732a5dbfd3a3013218a6f1955d74c1bc41ecc407e819ba1788bbf6`, 4 CPU, 1 GiB, AI delay 0 ms, storage delay 100 ms.
- Final observed MVC and mock state before cleanup: running, restart count 0, OOMKilled false.
- Mock `requestCounts` object was present. The `POST /analyze/face` key was absent and is therefore treated as zero for this specific endpoint count; `aiCompleted=0` and `aiMaxInFlight=0`. The no-network contract passed.

## Validity decision

The parent runner's generated `measurement-validity.json` is not authoritative: it reflects incomplete post-processing and reports the preflight state (`composeStarted=false`, `performanceWorkloadStarted=false`). The preserved client process, result, accounting, observer, runtime, final-state, and no-network artifacts prove that the workload did start and completed with valid accounting. This salvage record therefore classifies the run as `SALVAGED_VALID` and `STABLE`.

## Claim boundary

Under this run's REAL-payload inbound path, AI request-body construction, and production-equivalent Jackson JSON serialization path, the prior MVC collapse was not reproduced. This evidence does not establish that Jackson is irrelevant and does not identify RestTemplate, Apache HttpClient, socket behavior, or another root cause. It also does not modify or invalidate prior full-AI collapse evidence.
