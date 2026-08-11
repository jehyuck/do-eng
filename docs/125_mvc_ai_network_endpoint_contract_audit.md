# MVC AI Network / Endpoint Contract Audit

## Scope

This audit used one fresh idle runtime and direct contract checks only. No performance workload, VU run, source change, mock change, Compose base-file change, or WebFlux run was performed.

- HEAD at audit start: `16219727e7b455c5c056336aa9b4aa72e259c665`
- Compose project: `doeng-mvcdiag-network-audit-001`
- MVC runtime: CPU 2, memory 3 GiB, Tomcat 400, HTTP pool 400, DB pool 10, Xms 512m, Xmx 2048m
- Mock runtime: CPU 4, memory 1 GiB, AI result true, status 200, delay 0 ms

## Runtime and network

The MVC container and `experiment-mock` shared `doeng-mvcdiag-network-audit-001_default`. Docker network inspection showed the MVC aliases `mvc` and the mock aliases `experiment-mock`; the mock resolved from inside MVC with `getent hosts experiment-mock` to `192.168.128.2`.

- `NETWORK_CONTRACT=PASS`
- `MOCK_SERVICE_ALIAS_PRESENT=YES`
- `DNS_RESOLUTION=PASS`
- `RESOLVED_IP=192.168.128.2`

MVC environment inspection showed:

```text
DOENG_EXTERNAL_AI_BASE_URL=http://experiment-mock:9100/analyze
DOENG_HTTP_CONNECT_TIMEOUT_MS=2000
DOENG_HTTP_RESPONSE_TIMEOUT_MS=10000
```

The configured base URL matches the expected value: `AI_BASE_URL_CONTRACT=PASS`.

## Effective endpoint contract

The MVC `AiClient` constructs `faceUrl` as `properties.getAiBaseUrl() + "/face"`. Therefore the effective endpoint is:

```text
http://experiment-mock:9100/analyze/face
```

The mock source lists `/analyze/face`, `/analyze/object`, and `/analyze/doodle`; it does not list `/analyze` as an analyze endpoint.

From inside the MVC container, with the same JSON `{ "image": "data:image/jpeg;base64,..." }` schema:

| Payload | Configured `/analyze` | Effective `/analyze/face` |
|---|---:|---:|
| SMALL, 1024 bytes | HTTP 404, `{"error":"not found"}` | HTTP 200, result true |
| REAL, 265745 bytes | HTTP 404, `{"error":"not found"}` | HTTP 200, result true |

Effective endpoint elapsed times were 5.474 ms for SMALL and 14.149 ms for REAL. The returned image body was not committed; only compact status/body metadata was retained.

The initial `/analyze/face` probes made with BOM-prefixed temporary JSON were rejected as invalid JSON (HTTP 400). The corrected UTF-8 JSON without BOM produced the two HTTP 200 responses above; this was an audit request-construction artifact, not an application workload result.

Accordingly:

- `ANALYZE_ENDPOINT_CONTRACT=PASS` when evaluated through the MVC base-URL-plus-`/face` construction
- `STATIC_ADDRESS_MISMATCH=REJECTED`
- `REAL_PAYLOAD_DOWNSTREAM_CONTRACT_FAILURE=NO`

## Mock metrics

After the corrected SMALL and REAL effective-endpoint requests, mock metrics reported `aiCompleted=2`, `aiMaxInFlight=1`, and `POST /analyze/face=4`. The four observed endpoint requests include two initial malformed audit probes and the two corrected successful probes; the corrected SMALL and REAL requests are confirmed by their HTTP 200 responses.

- `MOCK_METRICS_SMALL_CONFIRMED=YES`
- `MOCK_METRICS_REAL_CONFIRMED=YES`

## Historical T02 error evidence

Preserved T02 client result artifacts show, for `MVC-DIAG-T02-CLOSURE-001`, `MVC-DIAG-T02-AI0-001`, and `MVC-DIAG-T02-AI0-MOCKCAP-001`:

- connection errors: 0 in each run
- HTTP 4xx: 0 in each client result
- HTTP 5xx: 0 in each client result
- timeout errors: recorded as `This operation was aborted`, matching the client timeout classification

The compact T02 run directories do not contain application stdout/stderr captures, so application-log searches for `UnknownHostException`, `ConnectException`, `Connection reset`, `SocketTimeoutException`, `ResourceAccessException`, and related server exception text are `NOT_CAPTURED`. The fresh audit runtime log contained no matching network error; it was startup-only and not a T02 collapse log.

Therefore the audit records:

```text
UNKNOWN_HOST_ERRORS=0 in preserved client artifacts; application logs NOT_CAPTURED
CONNECTION_REFUSED_ERRORS=0 in preserved client artifacts; application logs NOT_CAPTURED
CONNECTION_RESET_ERRORS=0 in preserved client artifacts; application logs NOT_CAPTURED
HTTP_4XX_ERRORS=0 in preserved T02 client artifacts
HTTP_5XX_ERRORS=0 in preserved T02 client artifacts
NETWORK_ERROR_LOG_MATCHES=NOT_CAPTURED for historical application logs
```

## Closure impact

The fresh network, DNS, base-URL, and effective `/analyze/face` checks pass. The direct `/analyze` 404 is explained by the explicit `/face` suffix in the MVC client and the mock’s endpoint contract; it is not evidence of a static address mismatch or a reason to revise the MVC diagnostic closure.

```text
MVC_DIAGNOSTIC_CLOSURE_REQUIRES_CORRECTION=NO
```

No low-level MVC root cause is established by this audit.

## Artifacts

Compact audit artifacts are under `experiment/results/MVC-DIAG-NETWORK-AUDIT-001/`, including network inspection, runtime contract, direct endpoint metadata, mock metrics, and historical client-error summary. The generated full request bodies remain local and are not committed.
