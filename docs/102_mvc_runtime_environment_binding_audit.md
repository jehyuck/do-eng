# MVC Historical vs Current Runtime Environment Binding Audit

## 1. Evidence inputs and limits

This was a static audit. No performance workload, application start, endpoint call, source/config/Compose/runner change, or build was performed.

Inputs:

- `docs/97_historical_mvc_vu160_evidence.md`
- `docs/98_historical_current_runtime_recovery.md`
- `docs/99_mvc_runtime_parity_audit.md`
- `docs/100_experiment_mock_semantic_diff.md`
- `docs/101_mvc_jar_semantic_parity.md`
- `experiment/results/RUN-20260731-252/run-config.json`
- `experiment/results/RUN-20260731-252/environment.json`
- `experiment/results/SERVICE1S-M001/run-config.json`
- `experiment/results/BRIDGE1S-MOCK-CURRENT-M001/run-config.json`
- SHA-matched historical Compose sources under `evidence-addendum/.../config-recovered/backend`
- Current `backend/docker-compose.experiment.yaml` and `experiment/compose/experiment-1-37-runtime.override.yml`
- Current MVC `application.yml` and Java binding classes

The historical run preserves hash-matched Compose source and run configuration, but not a historical rendered `docker compose config` or container inspect environment snapshot. Therefore historical values sourced from recovered Compose are `DECLARED`, not independently proven applied container values.

## 2. Historical environment inventory

Historical MVC run: `RUN-20260731-252`, Git HEAD recorded as `8e856468b36dcb1d7297afc05461af01d6dd6424`, Compose project `doeng-capacity-closure-20260731`.

The recovered historical stack used the base Compose file plus hash-matched overrides for T3-medium resources, HTTP pool 400, MVC threads 400, and mock headroom. The run configuration records AI `true/200/2000 ms`, storage `200/100 ms`, request timeout `10000 ms`, interval `1000 ms`, and 30 seconds of drain observation.

## 3. Current environment inventory

Current bridge/SERVICE1S MVC run: `BRIDGE1S-MOCK-CURRENT-M001`, Git HEAD `c32935f84349a95d93860cbe66cb84575361270f`, Compose project `doeng-bridge1s-mock-current-m001`.

The resolved SERVICE1S configuration records:

```text
HTTP_MAX_CONNECTIONS=400
HTTP_PENDING_MAX_COUNT=400
HTTP_CONNECT_TIMEOUT_MS=2000
HTTP_RESPONSE_TIMEOUT_MS=10000
HTTP_PENDING_ACQUIRE_TIMEOUT_MS=10000
DB_POOL_MAX_SIZE=10
MVC_MAX_THREADS=400
JAVA_XMS=512m
JAVA_XMX=2048m
APP_CPU=2.0
APP_MEMORY=3g
```

The application and downstream endpoint values are `experiment-mock` network URLs, with AI delay 2000 ms/status 200/result true and storage delay 100 ms/status 200.

## 4. Environment diff

| Variable | Historical MVC | Current MVC | Evidence / binding classification |
|---|---:|---:|---|
| `JAVA_TOOL_OPTIONS` | `-Xms512m -Xmx2048m -XX:+UseG1GC` | `-Xms512m -Xmx2g -XX:+UseG1GC` | Same effective heap; recovered/current Compose declaration |
| `DOENG_HTTP_MAX_CONNECTIONS` | `400` | `400` | Same; used by MVC Apache HttpClient pool |
| `DOENG_HTTP_PENDING_MAX_COUNT` | Not declared | `400` | Current-only Compose value, not bound or used by MVC Java |
| `DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT` | Not declared | Not present in MVC service; legacy key exists for Flux override only | Not used by MVC |
| `DOENG_HTTP_CONNECT_TIMEOUT_MS` | `2000` | `2000` | Same; used as Apache connect timeout |
| `DOENG_HTTP_RESPONSE_TIMEOUT_MS` | `10000` | `10000` | Same; used as Apache socket/read timeout |
| `DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS` | `10000` | `10000` | Same; used as Apache connection-request timeout |
| `DOENG_DB_POOL_MAX_SIZE` | `10` | `10` | Same; Hikari maximum pool size |
| `DOENG_MVC_MAX_THREADS` | `400` | `400` | Same; embedded Tomcat max threads |
| `DOENG_EXTERNAL_AI_BASE_URL` | `http://experiment-mock:9100/analyze` | Same | Same route; used by `AiClient` |
| `DOENG_EXTERNAL_TOKEN_VERIFICATION_URL` | `http://experiment-mock:9100/api/member/ai` | Same | Same route; used by `TokenClient` |
| `DOENG_EXTERNAL_STORAGE_BASE_URL` | `http://experiment-mock:9100` | Same | Same route; used by `HttpMissionImageStorage` |
| `DOENG_STORAGE_MODE` | Not present in recovered MVC service | Not present in current MVC service | It appears in the Flux service definition, not the MVC service; no MVC Java binding found |
| `SPRING_DATASOURCE_URL` | `jdbc:mariadb://mariadb:3306/doeng` | Same | Same declared JDBC URL; applied historical value not independently inspected |
| `SPRING_DATASOURCE_USERNAME` | `doeng` | `doeng` | Same declared value |
| `SPRING_DATASOURCE_PASSWORD` | `doeng-experiment-pass` | `doeng-experiment-pass` | Same declared value; secret is experiment placeholder in the Compose contract |
| `SPRING_PROFILES_ACTIVE` | `experiment` | `experiment` | Same profile declaration |

Historical and current values above are not promoted from contract defaults when an explicit recovered/current Compose or run-config value exists. Missing historical rendered environment remains a limitation.

## 5. Java binding map

| Variable | Spring property | Java binding | Actual use |
|---|---|---|---|
| `DOENG_MVC_MAX_THREADS` | `server.tomcat.threads.max` | Spring Boot embedded Tomcat | YES |
| `DOENG_DB_POOL_MAX_SIZE` | `spring.datasource.hikari.maximum-pool-size` | Spring Boot Hikari DataSource | YES |
| `DOENG_HTTP_MAX_CONNECTIONS` | `doeng.external.max-connections` | `ExternalServiceProperties.maxConnections` → `PoolingHttpClientConnectionManager.setMaxTotal/setDefaultMaxPerRoute` | YES |
| `DOENG_HTTP_CONNECT_TIMEOUT_MS` | `doeng.external.connect-timeout-ms` | `ExternalServiceProperties.connectTimeoutMs` → Apache `RequestConfig.setConnectTimeout` | YES |
| `DOENG_HTTP_RESPONSE_TIMEOUT_MS` | `doeng.external.response-timeout-ms` | `ExternalServiceProperties.responseTimeoutMs` → Apache `RequestConfig.setSocketTimeout` | YES |
| `DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS` | `doeng.external.pending-acquire-timeout-ms` | `ExternalServiceProperties.pendingAcquireTimeoutMs` → Apache `RequestConfig.setConnectionRequestTimeout` | YES |
| `DOENG_HTTP_PENDING_MAX_COUNT` | None | No MVC field/property/code reference | NO |
| `DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT` | None | No MVC field/property/code reference | NO |
| `DOENG_EXTERNAL_AI_BASE_URL` | `doeng.external.ai-base-url` | `ExternalServiceProperties.aiBaseUrl` → `AiClient` | YES |
| `DOENG_EXTERNAL_TOKEN_VERIFICATION_URL` | `doeng.external.token-verification-url` | `ExternalServiceProperties.tokenVerificationUrl` → `TokenClient` | YES |
| `DOENG_EXTERNAL_STORAGE_BASE_URL` | `doeng.external.storage-base-url` | `ExternalServiceProperties.storageBaseUrl` → `HttpMissionImageStorage` | YES |
| `DOENG_STORAGE_MODE` | None in MVC application resources | No MVC binding found; HTTP storage component is present directly | NO |
| `SPRING_DATASOURCE_*` | `spring.datasource.*` | Spring Boot JDBC/Hikari auto-configuration | YES |
| `SPRING_PROFILES_ACTIVE` | Profile selection | `application-experiment.yml` profile | YES |

Relevant source locations:

- `backend/doEngGameMvc/src/main/resources/application.yml:4,8-12,19-25`
- `backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/config/ExternalHttpClientConfig.java:16-40`
- `backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/client/TokenClient.java:19-29`
- `backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/client/AiClient.java:20-36`
- `backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/storage/HttpMissionImageStorage.java:22-40`
- `backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/config/MvcRuntimeMetrics.java:37-76`

## 6. HTTP connection pool and pending semantics

The MVC application creates one shared Apache `PoolingHttpClientConnectionManager` and one shared `RestTemplate`. `TokenClient`, `AiClient`, and `HttpMissionImageStorage` all receive that same `externalRestTemplate` bean. Therefore `DOENG_HTTP_MAX_CONNECTIONS=400` applies to token verification, AI, and storage requests through the same pool, with both total and per-route maxima set to 400.

`DOENG_HTTP_PENDING_MAX_COUNT` is not a Spring property and is not read by the MVC Java source. The current Compose value `400` does not create an MVC pending queue limit. `DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT` is likewise not used by MVC; the current override occurrence is Flux-only legacy input.

`HTTP_PENDING_SEMANTIC_DIFFERENCE: NOT_USED_BY_MVC`

Timeouts are distinct:

- mission client request timeout: `10000 ms`, load-generator behavior;
- Apache connect timeout: `2000 ms`;
- Apache socket/read response timeout: `10000 ms`;
- Apache connection-request/pending-acquire timeout: `10000 ms`.

Historical and current declared application timeout values are equal. The load-generator timeout is not an application timeout.

```text
HTTP_MAX_CONNECTION_PARITY: SAME
HTTP_PENDING_ACQUIRE_TIMEOUT_PARITY: SAME
HTTP_RESPONSE_TIMEOUT_PARITY: SAME
```

## 7. MVC threads and DB pool

`DOENG_MVC_MAX_THREADS` binds to `server.tomcat.threads.max`. Historical recovered MVC override and current resolved SERVICE1S configuration both specify 400.

`DOENG_DB_POOL_MAX_SIZE` binds to Hikari `maximum-pool-size`. Historical recovered base and current resolved configuration both specify 10.

```text
MVC_THREAD_RUNTIME_PARITY: SAME (declared/bound value; historical container inspect absent)
DB_POOL_RUNTIME_PARITY: SAME (declared/bound value; historical container inspect absent)
```

## 8. External endpoint semantics

Historical and current MVC Compose sources use the same Docker DNS service name, port, protocol, and paths:

```text
AI: http://experiment-mock:9100/analyze → MVC app appends /face
Token verification: http://experiment-mock:9100/api/member/ai
Storage base: http://experiment-mock:9100 → MVC appends /storage/object
```

The Compose project/network names differ between runs, but that is network naming/lifecycle isolation, not a route or protocol difference.

`EXTERNAL_ENDPOINT_PARITY: SAME`

## 9. Meaningful differences and root-cause relevance

The only current-vs-historical MVC environment difference found in the requested variables is the presence of `DOENG_HTTP_PENDING_MAX_COUNT=400` in the current Compose input. It is not consumed by the MVC application. The legacy pending-acquire maximum key is not present in the MVC service and is not consumed by MVC.

The effective values for all MVC-bound HTTP pool, timeout, Tomcat, DB, endpoint, datasource, and JVM settings are the same in the recovered/current declarations. Historical applied values cannot be fully proven because the historical rendered Compose output and container inspect environment are missing.

```text
HISTORICAL_ENV_RECOVERY: PARTIAL
MVC_RUNTIME_ENVIRONMENT_DIFFERENCE: NO_MEANINGFUL_DIFFERENCE
STRONGEST_RUNTIME_ENV_CANDIDATE: NONE
```

This audit does not promote the current experiment-mock instrumentation difference or workload scheduling difference into an MVC environment-binding conclusion.

## 10. Minimum next action

No single meaningful MVC environment variable was isolated. Do not propose pool/thread/timeout tuning from this audit. Any further causal test would need a separately approved bridge condition that changes only a proven runtime input.

## Constraints

```text
PERFORMANCE_LOAD_EXECUTED: NO
APPLICATION_STARTED: NO
CODE_CHANGED: NO
CONFIG_CHANGED: NO
```
