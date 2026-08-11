# Historical vs Current MVC Effective Runtime Capacity Audit

## Scope and disposition

This is a static artifact audit. No application, mock, database, Docker runtime, or performance workload was started. The comparison is limited to:

- Historical MVC: `RUN-20260731-252`, raw closure bundle under `DoEng-WebFlux-Capacity-Closure/raw/RUN-20260731-252`.
- Current MVC: `I1S-AI1S-M001`, using only `experiment/results/I1S-AI1S-M001/**` and the canonical pair index `experiment/results/I1S-AI1S-PAIR001-artifact-index.json`.
- Current evidence bundle commit: `4a19e9dcaaa8c0f34c35cf0cb08fe5443fcd20bf`.

The historical bundle records Git head `8e856468b36dcb1d7297afc05461af01d6dd6424` and the current M001 runtime identity records Git head `4c7478bd0a837ff651852f73eee6a0a83e1cdce0`. The current runtime identity is not replaced by the evidence-bundle commit identifier.

## Declared resource and application binding comparison

The two run configurations identify the same declared MVC resource contract:

| Item | Historical RUN-252 | Current M001 | Evidence status |
|---|---:|---:|---|
| Application CPU | `2.0` | `2.0` | declared parity |
| Application memory | `3g` | `3g` | declared parity |
| MVC Tomcat max threads | `400` | `400` | declared/bound parity |
| MVC outbound HTTP max connections | `400` | `400` | declared/bound parity |
| HTTP pending max | `400` | `400` | current resolved config; historical applied value not independently rendered |
| DB pool max | `10` | `10` | declared/bound parity |
| JVM Xms/Xmx | `512m` / `2048m` | `512m` / `2048m` | declared parity |

Historical `run-config.json` records the base Compose file plus the hash-matched T3-medium, HTTP-pool-400, MVC-threads-400, and mock-headroom overrides. The historical run does not preserve a rendered `docker compose config` or a container inspect environment snapshot. Accordingly, historical values above are declared/recovered values, not independently proven applied container values. Current M001 preserves the resolved configuration and runtime identity, but not a HostConfig/cgroup snapshot.

## Effective CPU

`HISTORICAL_EFFECTIVE_CPU`: **NOT_PROVEN**. Historical `container-stats.jsonl` reports observed CPU percentages, including values above 100%, but does not report NanoCPUs, CPU quota/period, cpuset, or cgroup throttling counters. An observed CPU percentage is not an effective CPU limit.

`CURRENT_EFFECTIVE_CPU`: **NOT_PROVEN**. M001 preserves the declared `APP_CPU=2.0`, but its result directory has no Docker inspect, HostConfig, cgroup CPU quota, cpuset, or throttling evidence.

Therefore the declared CPU settings match, but effective CPU enforcement parity is not established.

`CURRENT_CPU_THROTTLING`: **NOT_CAPTURED**. No current `cpu.stat`/throttled-time evidence is present. Historical throttling counters are also absent.

## JVM-visible processors

Neither raw bundle contains JVM `Runtime.availableProcessors()` output, JVM startup diagnostics, `/proc/cpuinfo` capture, or an equivalent processor-visible runtime record.

- `HISTORICAL_JVM_PROCESSORS`: **NOT_AVAILABLE**
- `CURRENT_JVM_PROCESSORS`: **NOT_AVAILABLE**
- `JVM_VISIBLE_CPU_PARITY`: **NOT_PROVEN**

The host metadata is not a substitute for the processor count visible to the application JVM.

## Effective memory

Historical `container-stats.jsonl` shows MVC samples formatted as `MemUsage: ... / 3GiB`, consistent with the declared 3 GiB container memory limit. This is the only historical runtime-limit-shaped evidence found; no historical inspect/HostConfig artifact is preserved to independently verify the limit.

Current M001 preserves `APP_MEMORY=3g` in `resolved-experiment-config.json`, but does not preserve a Docker inspect memory limit or cgroup memory limit. Thus:

- `HISTORICAL_EFFECTIVE_MEMORY`: **3 GiB observed by Docker stats; independently applied limit NOT_PROVEN**
- `CURRENT_EFFECTIVE_MEMORY`: **NOT_CAPTURED; declared 3 GiB**
- `EFFECTIVE_MEMORY_PARITY`: **NOT_PROVEN**

Observed memory usage must not be interpreted as evidence of equal effective capacity.

## Host and Docker runtime

The captured host metadata is identical in the two environment artifacts:

- Windows 11 Home `10.0.26200`
- Intel Core Ultra 7 255H
- 16 logical processors
- 33,756,008,448 bytes host memory
- Docker client/server `29.4.1`, Docker Desktop `4.71.0`
- `desktop-linux`, WSL2 kernel `6.6.87.2-microsoft-standard-WSL2`

`HOST_RUNTIME_PARITY`: **PASS for the captured host/tool identity; NOT_PROVEN for all runtime enforcement state**. This does not close the missing container inspect, cgroup, or JVM evidence.

## HTTP runtime

The MVC source/config audit establishes the same declared binding of `DOENG_HTTP_MAX_CONNECTIONS=400` to the shared Apache HttpClient pool, with Tomcat worker threads separately bound to `DOENG_MVC_MAX_THREADS=400`. The historical run does not preserve rendered Compose or container environment evidence, and neither bundle supplies a runtime pool-state snapshot.

`HTTP_RUNTIME_PARITY`: **DECLARED_SAME_EFFECTIVE_NOT_PROVEN**.

The HTTP pool value is not a servlet worker-thread value. No claim is made that the two runs had identical effective connection availability at every instant.

## Capacity conclusion

`RUNTIME_CAPACITY_DIFFERENCE`: **INCONCLUSIVE**. Declared application resources and MVC bindings match, and the captured host/tool identity matches. However, effective CPU quota/cpuset, throttling, JVM-visible processors, and current container memory enforcement are not preserved for both runs. The artifacts therefore cannot establish whether an effective runtime-capacity difference explains the observed workload difference.

The historical/current scheduling-shape difference documented in `docs/108_historical_current_request_scheduling_shape_audit.md` is not a substitute for missing runtime-capacity evidence. Its discrepancy candidate is intentionally `WORKLOAD_SCHEDULER_SEMANTICS_INCONCLUSIVE`: the historical load-driver source and per-request timestamps are not available, so causal direction is not established.

## Evidence paths

- `DoEng-WebFlux-Capacity-Closure/raw/RUN-20260731-252/environment.json`
- `DoEng-WebFlux-Capacity-Closure/raw/RUN-20260731-252/run-config.json`
- `DoEng-WebFlux-Capacity-Closure/raw/RUN-20260731-252/container-stats.jsonl`
- `experiment/results/I1S-AI1S-M001/environment.json`
- `experiment/results/I1S-AI1S-M001/run-config.json`
- `experiment/results/I1S-AI1S-M001/resolved-experiment-config.json`
- `experiment/results/runtime-identities/I1S-AI1S-M001/runtime-identity.json`
- `experiment/results/I1S-AI1S-PAIR001-artifact-index.json`
- `docs/102_mvc_runtime_environment_binding_audit.md`
- `docs/108_historical_current_request_scheduling_shape_audit.md`

```text
AUDIT:
HISTORICAL_CURRENT_EFFECTIVE_RUNTIME_CAPACITY

DOC108_CAUSAL_CORRECTION:
PASS

DECLARED_RESOURCE_PARITY:
PASS (declared/bound values; historical applied values not fully proven)

EFFECTIVE_CPU_PARITY:
NOT_PROVEN

HISTORICAL_EFFECTIVE_CPU:
NOT_PROVEN

CURRENT_EFFECTIVE_CPU:
NOT_PROVEN

JVM_VISIBLE_CPU_PARITY:
NOT_PROVEN

HISTORICAL_JVM_PROCESSORS:
NOT_AVAILABLE

CURRENT_JVM_PROCESSORS:
NOT_AVAILABLE

CURRENT_CPU_THROTTLING:
NOT_CAPTURED

EFFECTIVE_MEMORY_PARITY:
NOT_PROVEN

HISTORICAL_EFFECTIVE_MEMORY:
3 GiB observed by Docker stats; applied limit not independently proven

CURRENT_EFFECTIVE_MEMORY:
NOT_CAPTURED; declared 3 GiB

HOST_RUNTIME_PARITY:
PASS for captured host/tool identity; full enforcement parity not proven

HTTP_RUNTIME_PARITY:
DECLARED_SAME_EFFECTIVE_NOT_PROVEN

RUNTIME_CAPACITY_DIFFERENCE:
INCONCLUSIVE

HISTORICAL_DISCREPANCY_CANDIDATE:
RUNTIME_CAPACITY_INCONCLUSIVE

PERFORMANCE_LOAD_EXECUTED:
NO

PRODUCTION_CODE_CHANGED:
NO

LOAD_DRIVER_CHANGED:
NO
```
