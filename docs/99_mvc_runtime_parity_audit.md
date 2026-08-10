# MVC Historical vs Current Runtime Parity Audit

## 1. Inputs and restrictions

This audit used no performance workload, endpoint call, application start, source/config change, branch reset, or compose change. Temporary diagnostic containers were created only with an overridden shell entrypoint, never with the application entrypoint; they were removed after inspection.

Compared inputs:

- Historical `RUN-20260731-252` raw artifacts and `run-config.json`.
- Current `SERVICE1S-M001` raw artifacts and `run-config.json`.
- Historical image `doeng-capacity-closure-20260731-mvc:latest`.
- Current image `doeng-service1s-mvc400-mvc:latest`.
- Historical compose files recovered by SHA from `evidence-addendum/_superseded_first_build_20260731/provenance/config-recovered/backend`.
- Current `backend/docker-compose.experiment.yaml` and `experiment/compose/experiment-1-37-runtime.override.yml`.

## 2. MVC JAR parity

Both images contain the same `/app/app.jar` SHA-256:

```text
3e846b8be2f00d63bda6793da7cd2a795c9dda8778ab14f087f0d20da9faed5f
```

The JAR size is 22,790,079 bytes. ZIP entry lists are also identical: 156 entries in each image, including `BOOT-INF/classes/application.yml`.

```text
MVC_JAR_PARITY:
SAME
```

This establishes application-binary identity, not equality of the compose-provided runtime environment.

## 3. Docker application image parity

| Property | Historical MVC image | Current SERVICE1S MVC image | Result |
|---|---|---|---|
| Image ID | `sha256:81f580e585cde6588c71aca72041faeb09b89b87ffc375d473d41f75a959e05e` | `sha256:2dfbff77ea445c0f41e4dcebf47f1beb5d5ca810a24530022549052daf11ce51` | ID differs |
| Architecture / OS | `amd64` / `linux` | `amd64` / `linux` | same |
| Created | `2026-07-29T08:32:48.345556053Z` | `2026-07-29T08:32:48.345556053Z` | same |
| RootFS layer list | 8 layers | same 8 layers | same |
| Entrypoint | `java -jar /app/app.jar --server.port=8000` | same | same |
| Working directory | `/app` | `/app` | same |
| Exposed ports | `8000/tcp`, `9091/tcp` | same | same |
| Base image labels | Ubuntu 26.04 | same | same |

`docker history --no-trunc` is identical through the Java runtime/base layers and the application JAR copy. The only inspected Config difference is the Compose project label (`doeng-capacity-closure-20260731` versus `doeng-service1s-mvc400`).

```text
MVC_IMAGE_RUNTIME_PARITY:
SAME (apart from Compose project labeling)
```

The image ID difference therefore does not indicate a different Java/base runtime; it is explained by the different Compose project label in the image metadata.

## 4. Java and OS runtime parity

The overridden-shell diagnostic produced the same results for both images:

```text
Java vendor/runtime: Temurin OpenJDK
Java version: 11.0.31+11
VM: OpenJDK 64-Bit Server VM
OS: Ubuntu 26.04 LTS
Architecture: x86_64 / amd64
Kernel: Linux 6.6.87.2-microsoft-standard-WSL2
nofiles: 1048576
```

`java -XshowSettings:vm -version` reported the same estimated maximum heap of 3.84G in the diagnostic shell. This is the image default before any compose-provided `JAVA_TOOL_OPTIONS` is applied.

```text
JAVA_RUNTIME_PARITY:
SAME
```

## 5. Historical Compose source recovery

All six SHA-matched historical compose files were recovered locally:

| Historical file | SHA-256 |
|---|---|
| `docker-compose.experiment.yaml` | `f858b3467be96c64490aec725a2f917a7baef078566ee3db14011845f03ed5db` |
| `docker-compose.app-instance-t3-medium.yaml` | `8659fa51f2003f5f34b350ec0432d8dbc7b4bf69814a3694c6de9728fc5672b4` |
| `docker-compose.mock-headroom-4cpu.yaml` | `eeb89c0f2d23cc1685e0b47b6bfea2f02606a39187b40ed075542c86cdefba5b` |
| `docker-compose.http-pool-400.yaml` | `025c216363b85e4ce47eea0d4eb0753022cc8a05d14b64de96261321249200d7` |
| `docker-compose.mock-memory-headroom.yaml` | `bc513adb59d2cc8cfa10ed95d25658a446af1c6145e4dcdb7df9d9900648ad1b` |
| `docker-compose.mvc-threads-400.yaml` | `feacb89ffe673f25460311ca81ef06bf61ff93631e4f8de5baa97b31579c927b` |

The source files are available in the evidence-addendum recovery tree, but the historical rendered `docker compose config` output and the historical application container inspect capture are not present. Therefore the source is recovered, while every applied runtime value cannot be independently proven from an inspect snapshot.

```text
HISTORICAL_COMPOSE_SOURCE:
PARTIAL
```

## 6. Historical/current Compose semantic comparison

The recovered historical stack was the historical base plus these effective overrides:

- application CPU 2.00 and memory 3g;
- JVM `-Xms512m -Xmx2048m`;
- HTTP max connections 400;
- MVC max threads 400;
- experiment-mock CPU 4.00 and memory 1g;
- MariaDB base limit 1 CPU and 1g memory;
- DB pool 10 in the historical base.

Current SERVICE1S source expresses the same principal resource values through the current base and runtime override: application 2.0 CPU / 3g, JVM 512m / 2g, HTTP max 400, pending 400, DB pool 10, MVC max threads 400, experiment-mock 4 CPU / 1g, and MariaDB 1 CPU / 1g.

However, the semantic inputs are not identical. Current runtime override additionally supplies or explicitly controls:

- `DOENG_HTTP_PENDING_MAX_COUNT=400`;
- legacy `DOENG_HTTP_PENDING_ACQUIRE_MAX_COUNT=800`;
- admission and observation switches;
- current mock result/delay/status and strict-auth settings.

Historical base/override source and current source also use different build contexts, Compose project names, and port/project wiring. The historical raw run does not preserve the fully rendered environment or container inspect, so “same declared value” is not equivalent to “same applied runtime value” for fields without a historical runtime snapshot.

```text
COMPOSE_SEMANTIC_PARITY:
DIFFERENT
```

## 7. Resource-limit classification

| Resource | Historical evidence | Current evidence | Classification |
|---|---|---|---|
| MVC CPU / memory | exact hash-matched override: 2.00 / 3g | current config/override: 2.0 / 3g | same declared value; applied historical runtime not independently inspected |
| JVM Xms / Xmx | exact override: 512m / 2048m | current override: 512m / 2g | same declared value |
| MVC max threads | exact hash-matched override: 400 | current config: 400 | same declared value |
| HTTP max connections | exact hash-matched override: 400 | current config/override: 400 | same declared value |
| HTTP pending | historical base has no explicit pending-max key | current override: 400 | historical actual not proven |
| DB pool | historical base: 10 | current base/config: 10 | same declared value |
| MariaDB CPU / memory | historical base: 1 / 1g | current base: 1 / 1g | same declared value |
| experiment-mock CPU / memory | historical overrides: 4 / 1g | current override: 4 / 1g | same declared value |

```text
HISTORICAL_APP_CPU_LIMIT:
CONFIRMED from hash-matched compose source; historical container application not inspected

HISTORICAL_APP_MEMORY_LIMIT:
CONFIRMED from hash-matched compose source; historical container application not inspected

APP_RESOURCE_PARITY:
SAME for explicitly matched declared limits; NOT_PROVEN as full applied-runtime parity
```

## 8. Dependency image comparison

### MariaDB

Both historical and current compose sources specify `mariadb:10.11`. The local image is:

```text
sha256:be981e4113326ada8d6004174dd09eeaefc03094037f811182a52d4f2e737350
MariaDB 10.11.18+maria~ubu2204
```

The historical run did not preserve a dependency image ID, so the local image cannot prove that this exact image was the one running on 2026-07-31.

```text
MARIADB_RUNTIME_PARITY:
NOT_PROVEN (same declared tag; historical runtime ID absent)
```

### experiment-mock

| | Historical | Current SERVICE1S MVC |
|---|---|---|
| Image | `doeng-capacity-closure-20260731-experiment-mock:latest` | `doeng-service1s-mvc400-experiment-mock:latest` |
| Image ID | `sha256:60f473741f2c3be6da1f07f5069ac2c5c8c3e9e61cac4d8da83d4f8e0a18754a` | `sha256:6fcbe49ab0505f003ff17eaf187e5c813a8cea107a30412b2d4f4e79848546d3` |
| `/app/server.js` SHA-256 | `d3951b3b616062ca160db3ad063362a77b4a4b4fe4dbb70170e5d09c761e3de4` | `a335d8fabdd0210b9ae752d99254340db1639e3ec5b525d0f71d634e19b00286` |
| `/app/server.js` bytes | 11,174 | 16,207 |
| Node runtime | 20.20.2 | 20.20.2 |

The image layers are different at the final application layer and the contained server source differs. The historical/current raw `mock-control` values both declare AI 2000 ms / status 200 / true and storage 100 ms / status 200, but the mock implementation artifact is not identical.

```text
MOCK_RUNTIME_PARITY:
DIFFERENT
```

## 9. Final classification

```text
MVC_JAR_PARITY:
SAME

MVC_IMAGE_RUNTIME_PARITY:
SAME (apart from Compose project label)

JAVA_RUNTIME_PARITY:
SAME

HISTORICAL_COMPOSE_SOURCE:
PARTIAL

COMPOSE_SEMANTIC_PARITY:
DIFFERENT

APP_RESOURCE_PARITY:
SAME for matched declared limits; NOT_PROVEN as full applied-runtime parity

MARIADB_RUNTIME_PARITY:
NOT_PROVEN

MOCK_RUNTIME_PARITY:
DIFFERENT

RUNTIME_EXPLANATION:
CONFIRMED_CANDIDATE
```

The confirmed candidate differences are Compose/runtime input semantics and the experiment-mock artifact. The application image, Java runtime, base OS, rootfs, and MVC JAR do not explain the discrepancy: they are the same at the inspected image/runtime level. This audit does not establish which Compose/mock difference caused the result difference, because historical rendered config, dependency runtime identity, and container-level resource inspect are missing.

The current `mission-load.js` reconnect-ramp behavior is not treated as a proven cause. Historical client timestamps are absent, and `maxInFlight` alone cannot distinguish scheduler changes from response/backlog accumulation.

## 10. Minimum remaining evidence

- Historical application/dependency container inspect and rendered Compose output.
- Historical dependency image IDs from the run itself.
- Historical client-side request start/completion timestamps.
- A controlled comparison isolating the recovered mock/runtime difference, if later approved.

No follow-up performance workload is executed or authorized by this audit.
