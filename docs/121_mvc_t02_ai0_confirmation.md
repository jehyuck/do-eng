# MVC T02 AI0 Confirmation

## Execution

- HEAD: `e6c43addfec66cb6839692c2815543a44552ec66`
- Run: `MVC-DIAG-T02-AI0-001`
- Compose project: `doeng-mvcdiag-t02-ai0-001`
- Execution: one 60-second foreground Node measurement; no T03 or matrix rerun
- WebFlux executed: no

## Controlled contract

The run used `MODE=AI`, `PAYLOAD_PROFILE=REAL`, 160 active users, 1000 ms interval, 60000 ms duration, and a 10000 ms request timeout. The AI mock delay was `0 ms`; storage delay remained `100 ms`. Runtime resources remained CPU 2, memory 3 GiB, Tomcat 400, HTTP connections 400, and DB pool 10, with JVM Xms 512m/Xmx 2048m.

The fixture was `image/arc.jpg` with 265745 bytes and SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`. The request JSON size was 354363 bytes.

`T02_AI0_CONTRACT_PARITY=FAIL` is intentional: AI delay is the single changed variable relative to canonical T02 AI1000. The remaining recorded load, fixture, runtime, and resource fields were held constant.

## Gates and process validity

- Startup gate: PASS
- Runtime contract: PASS
- Node exit code: 0
- Result file: present
- Started/completed: 9228/9228
- Container restart: 0
- OOMKilled: false
- Observer valid: true

Therefore `AI0_MEASUREMENT_VALID=YES`.

## Client result

| Metric | Value |
|---|---:|
| Started | 9228 |
| Completed | 9228 |
| HTTP 200 | 64 |
| Timeout | 9166 |
| Connection error | 0 |
| Success rate | 0.6935% |
| Timeout rate | 99.3065% |
| Successful RPS | 1.0667 |
| Total RPS | 153.8 |
| p50 | 10033 ms |
| p95 | 10131 ms |
| p99 | 10193 ms |
| Max in-flight | 1582 |

Classification by the registered rule is `COLLAPSE` (success below 80% and timeout at least 20%).

## Observer and runtime evidence

- Observer samples: 17
- Successful application samples: 14
- Successful mock samples: 5
- Readiness failures: 17
- Tomcat busy max: 400
- Tomcat queue max: 6796
- HTTP active max: 400
- HTTP pending max: 0
- AI in-flight max: 27; maximum observed AI in-flight field: 28
- Maximum observed AI completed: 232
- Storage in-flight max: 0; storage completed max: 0
- MVC container restart: 0
- MVC OOMKilled: false

The final direct mock metrics request was unavailable after the measurement and is preserved as `mock-metrics-final.json` with the unavailable marker. Observer validity remained true under the existing observer contract.

## Comparison boundary

- T01 canonical state: `STABLE`
- T02 AI1000 canonical state: `COLLAPSE`
- T02 AI0 state: `COLLAPSE`
- `WAIT_SENSITIVITY_CONFIRMED=NO`
- `AI_CALL_PATH_SENSITIVITY=YES`
- First unstable boundary: T02
- Root cause: `DO_NOT_ASSERT_YET`

AI0 did not restore stability under the registered workload and resources. This confirms an observed AI-call-path sensitivity for this condition, but does not by itself establish a specific blocking-I/O or MVC root cause.

## Artifact index

Run artifacts are under `experiment/results/MVC-DIAG-T02-AI0-001/`. The committed compact evidence includes `startup-gate.json`, `runtime-contract.json`, `client-process-contract.json`, client stdout/stderr logs, `observer.summary.json`, `container-state.json`, and `mock-metrics-final.json`. Large raw request/progress/observer streams remain local in the run directory.
