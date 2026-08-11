# MVC T02 AI0 Mock Capacity Isolation

## Execution

- HEAD: `6b8f7c47ba3f9f26149c607a14a3c4a9d08010ae`
- Run: `MVC-DIAG-T02-AI0-MOCKCAP-001`
- Compose project: `doeng-mvcdiag-t02-ai0-mockcap-001`
- One fresh 60-second foreground Node measurement only
- T03, additional AI-delay runs, and WebFlux were not executed

## Controlled contract

The run retained the preceding AI0 contract: `MODE=AI`, `PAYLOAD_PROFILE=REAL`, 160 active users, 1000 ms interval, 60000 ms duration, 10000 ms request timeout, AI delay 0 ms, storage delay 100 ms, and the same target and fixture.

The fixture was `image/arc.jpg`, 265745 bytes, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`; request JSON size was 354363 bytes. MVC resources remained CPU 2, memory 3 GiB, Tomcat 400, HTTP connections 400, DB pool 10, JVM Xms 512m/Xmx 2048m.

The only intended variation was `experiment-mock` capacity:

| Resource | Baseline AI0 | Mock-capacity run |
|---|---:|---:|
| CPU | 0.5 | 4.0 |
| Memory | 256 MiB | 1 GiB |

The base Compose file and mock/application images were not changed.

## Runtime gates

- Startup gate: PASS
- MVC runtime contract: PASS
- Mock runtime contract: PASS
- Mock NanoCPUs: 4000000000
- Mock memory bytes: 1073741824
- MVC NanoCPUs: 2000000000
- MVC memory bytes: 3221225472
- MVC restart/OOM: 0 / false
- Mock restart/OOM: 0 / false
- Node exit code: 0
- Observer valid: true

`CONTROLLED_FIELDS_PARITY=PASS`, with mock capacity as the intended variation.

## Client result

| Metric | Value |
|---|---:|
| Started | 9572 |
| Completed | 9572 |
| HTTP 200 | 5901 |
| Timeout | 4079 |
| Connection error | 0 |
| Success rate | 61.6486% |
| Timeout rate | 42.6139% |
| Successful RPS | 98.35 |
| Total RPS | 159.5333 |
| p50 | 8580 ms |
| p95 | 10020 ms |
| p99 | 10033 ms |
| Max in-flight | 1600 |

By the registered rule, this is `COLLAPSE` because success is below 80% and timeout is at least 20%.

## Observer and downstream evidence

- Observer samples: 19
- Successful application samples: 14
- Successful mock samples: 14
- Readiness failures: 16
- Tomcat busy max: 400
- Tomcat queue max: 1917
- HTTP active max: 400
- HTTP pending max: 0
- AI in-flight max: 137
- AI completed max observed: 6197
- Storage in-flight max: 0
- Storage completed max observed: 0
- Final mock metrics endpoint: captured successfully

Relative to baseline AI0, the expanded mock capacity materially improved the observed completion rate and reduced the Tomcat queue, but it did not restore the run to the registered STABLE classification.

## Isolation conclusion

- Base T02 AI0 classification: `COLLAPSE`
- Mock-capacity classification: `COLLAPSE`
- `MOCK_CAPACITY_CONFOUNDER_CONFIRMED=NO`
- `FIRST_UNSTABLE_BOUNDARY=T02`
- `ROOT_CAUSE=DO_NOT_ASSERT_YET`

The registered confirmation criterion required the expanded-capacity run to become STABLE. That criterion was not met. This run therefore does not justify attributing the original collapse solely to the 0.5 CPU/256 MiB mock capacity, and it does not establish the MVC blocking-architecture root cause.

## Artifact locations

Run artifacts are under `experiment/results/MVC-DIAG-T02-AI0-MOCKCAP-001/`. The run-specific `mock-capacity.override.yml`, startup/runtime contracts, client process contract, observer summary/stream, container states, and mock metrics are preserved. Large raw client result/progress files remain local in the run directory.
