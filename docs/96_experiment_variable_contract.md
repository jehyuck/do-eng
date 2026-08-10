# Experiment Variable Contract

이 문서는 WebFlux/MVC 실험 조건의 단일 외부 설정 계약이다. 기본값은 현재 runner와 Compose의 기존 동작을 보존한다. `-ConfigPath`를 사용하면 같은 구조의 JSON으로 한 실행의 조건을 명시할 수 있고, runner는 결과 디렉터리에 `resolved-experiment-config.json`을 저장한다.

실제 performance workload는 이 변경에서 실행하지 않았다.

## Canonical variables

| Variable | Purpose | Default | Consumer | Scope | Unit |
|---|---|---:|---|---|---|
| `ACTIVE_MISSIONS` | active logical missions/users | `2` | runner → `mission-load.js` | Common | count |
| `LOAD_SCENARIO` | `single-success` or `reconnect-ramp` | `single-success` | runner → load | Common | enum |
| `ACCOUNTING_MODE` | legacy/corrected result accounting | `legacy` | runner → load | Common | enum |
| `INTERVAL_MS` | frame interval | `3000` | runner → load | Common | ms |
| `DURATION_MS` | load duration | `3500` | runner → load | Common | ms |
| `REQUEST_TIMEOUT_MS` | client request timeout | `10000` | runner → load | Common | ms |
| `ARRIVAL_MODE` | aligned/staggered scheduling | `aligned` | runner → load | Common | enum |
| `INITIAL_ACTIVE_USERS` | initial users for reconnect-ramp | `0` (effective mission count outside ramp) | runner → load | Common | count |
| `ACTIVATION_STEP_USERS` | activation step for reconnect-ramp | `0` (effective mission count outside ramp) | runner → load | Common | count |
| `ACTIVATION_INTERVAL_MS` | activation interval | `3000` | runner → load | Common | ms |
| `RECONNECT_DELAY_MS` | reconnect delay | `3000` | runner → load | Common | ms |
| `WARMUP_MS` | reserved orchestration warmup metadata | `0` | runner resolved config only | Common | ms |
| `DRAIN_OBSERVATION_SECONDS` | post-load drain observation | `0` | runner → load | Common | seconds |
| `AI_RESULT` → `MOCK_AI_RESULT` | mock AI result | `true` in runtime control | runner control → Compose/mock | Common | boolean |
| `AI_DELAY_MS` → `MOCK_AI_DELAY_MS` | AI mock delay | `500` runner default | runner control → Compose/mock | Common | ms |
| `AI_STATUS` → `MOCK_AI_STATUS` | AI mock status | `200` | runner control → Compose/mock | Common | HTTP status |
| `STORAGE_DELAY_MS` → `MOCK_STORAGE_DELAY_MS` | storage mock delay | `100` | runner control → Compose/mock | Common | ms |
| `STORAGE_STATUS` → `MOCK_STORAGE_STATUS` | storage mock status | `200` | runner control → Compose/mock | Common | HTTP status |
| `APP_CPU` | application container CPU limit | Compose default | Compose | Common | CPU |
| `APP_MEMORY` | application container memory limit | Compose default | Compose | Common | Docker memory |
| `HTTP_MAX_CONNECTIONS` | outbound HTTP maximum connections | Compose/application default | Compose → `DOENG_HTTP_MAX_CONNECTIONS` | Common | count |
| `HTTP_PENDING_MAX_COUNT` | outbound pending acquire limit | Compose/application default | Compose → `DOENG_HTTP_PENDING_MAX_COUNT` | Common | count |
| `HTTP_CONNECT_TIMEOUT_MS` | outbound connect timeout | application default | Compose → `DOENG_HTTP_CONNECT_TIMEOUT_MS` | Common | ms |
| `HTTP_RESPONSE_TIMEOUT_MS` | outbound response timeout | application default | Compose → `DOENG_HTTP_RESPONSE_TIMEOUT_MS` | Common | ms |
| `HTTP_PENDING_ACQUIRE_TIMEOUT_MS` | outbound pending acquire timeout | application default | Compose → `DOENG_HTTP_PENDING_ACQUIRE_TIMEOUT_MS` | Common | ms |
| `DB_POOL_MAX_SIZE` | database pool maximum | `10` | Compose → `DOENG_DB_POOL_MAX_SIZE` | Common | count |
| `MVC_MAX_THREADS` | embedded Tomcat worker maximum | `200` | Compose → `DOENG_MVC_MAX_THREADS` | MVC only | threads |
| `JAVA_XMS` | JVM initial heap | Compose default | Compose `JAVA_TOOL_OPTIONS` | Common | JVM memory |
| `JAVA_XMX` | JVM maximum heap | Compose default | Compose `JAVA_TOOL_OPTIONS` | Common | JVM memory |

## Configuration mapping

The JSON contract uses camelCase fields under `load`, `downstream`, `application`, `http`, `database`, `mvc`, and `jvm`. The runner accepts `-ConfigPath` and maps these fields to the existing process and application environment names. Application-facing `DOENG_*` names remain the existing canonical names; no legacy alias is removed.

## Current inventory

| Condition | Existing variable/parameter | Existing default | Current consumer | Hardcoded/parameter location | Scope |
|---|---|---:|---|---|---|
| load scheduling | `INTERVAL_MS`, `ARRIVAL_MODE`, `LOAD_SCENARIO` | 3000/aligned/single-success | `mission-load.js` | `experiment/load/mission-load.js`; runner exports | Common |
| client timeout | `REQUEST_TIMEOUT_MS` | 10000 | `mission-load.js` | runner parameter and load env | Common |
| AI/storage mock | `MOCK_AI_*`, `MOCK_STORAGE_*` | runner control defaults | mock control endpoint and Compose | runner + compose files | Common |
| application resources | `APP_CPU`, `APP_MEMORY` | Compose defaults | Docker Compose | `backend/docker-compose.experiment.yaml` and override | Common |
| outbound HTTP | `DOENG_HTTP_*` mapped from contract names | application/Compose defaults | Spring config | WebFlux/MVC `application.yml` | Common; pending max is WebFlux-specific |
| database pool | `DOENG_DB_POOL_MAX_SIZE` | 10 | R2DBC/Hikari | WebFlux/MVC `application.yml` | Common |
| Tomcat workers | `DOENG_MVC_MAX_THREADS` | 200 | MVC Spring config | MVC `application.yml` | MVC only |
| JVM heap | `JAVA_XMS`, `JAVA_XMX` | Compose defaults | `JAVA_TOOL_OPTIONS` | Compose service definitions | Common |

| Canonical contract field | Existing application name | Disposition |
|---|---|---|
| `http.maxConnections` | `DOENG_HTTP_MAX_CONNECTIONS` | Canonical mapping |
| `http.pendingMaxCount` | `DOENG_HTTP_PENDING_MAX_COUNT` / `DOENG_SHARED_POOL_PENDING_MAX_COUNT` fallback | Canonical mapping; legacy `DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT` retained but not consumed |
| `database.poolMaxSize` | `DOENG_DB_POOL_MAX_SIZE` | Canonical mapping |
| `mvc.maxThreads` | `DOENG_MVC_MAX_THREADS` | MVC-specific mapping |
| `application.cpu`, `application.memory` | `APP_CPU`, `APP_MEMORY` | Compose resource contract |
| `jvm.xms`, `jvm.xmx` | `JAVA_TOOL_OPTIONS` | Compose mapping; no new JVM tuning option |

Existing experiment-specific variables not listed here remain unchanged. No legacy setting is deleted.

## Resolved configuration

`resolved-experiment-config.json` is written beside `run-config.json`. It includes the implementation, all load/downstream/resource/pool/database/MVC/JVM fields, source (`parameter`, `config-file`, or `compose-default`), and the config file path when supplied. `WARMUP_MS` is recorded as metadata because the current runner has no warmup execution phase; it does not create a warmup workload.

## Validation scope

The validation for this change is static/config-only: a temporary JSON configuration is passed through the resolver and the resolved JSON plus Compose interpolation are checked. No application image is built and no smoke/performance workload is run.
