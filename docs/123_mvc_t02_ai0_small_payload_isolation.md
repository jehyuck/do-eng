# MVC T02 AI0 SMALL Payload Isolation

## Execution

- HEAD at execution: `e48bb086683c484d20e2fb8ab936b272d204aba0`
- Run: `MVC-DIAG-T02-AI0-SMALL-001`
- Compose project: `doeng-mvcdiag-t02-ai0-small-001`
- One fresh 60-second foreground Node measurement only
- T03, additional AI-delay runs, boundary matrix, and WebFlux were not executed

## Controlled contract

The run retained the T02 AI0 mock-capacity contract: `MODE=AI`, 160 active users, 1000 ms interval, 60000 ms duration, 10000 ms request timeout, AI delay 0 ms, storage delay 100 ms, MVC CPU 2/memory 3 GiB, Tomcat 400, HTTP connections 400, DB pool 10, JVM Xms 512m/Xmx 2048m, and mock CPU 4.0/memory 1 GiB.

The only intended workload variation was `PAYLOAD_PROFILE=REAL` to `SMALL`. The fixture source remained `image/arc.jpg`; the client used the SMALL profile’s 1024-byte binary payload.

`CONTROLLED_FIELDS_PARITY=PASS` with `INTENDED_VARIATION=PAYLOAD_SIZE_ONLY`.

## Payload evidence

| Field | Value |
|---|---:|
| Binary bytes | 1024 |
| Binary SHA-256 | `db63cba69f93ee70dbae93b4b279296ef7b4ddbf23ff766b638a9eccac20f3f4` |
| Base64 characters | 1368 |
| Request JSON bytes | 1403 |

## Runtime and validity gates

- Startup gate: PASS
- MVC runtime contract: PASS
- Mock runtime contract: PASS
- Mock NanoCPUs: 4000000000
- Mock memory bytes: 1073741824
- MVC restart/OOM: 0 / false
- Mock restart/OOM: 0 / false
- Node exit code: 0
- Observer valid: true
- Final mock metrics: captured

Therefore `MEASUREMENT_VALID=YES`.

## Client result

| Metric | Value |
|---|---:|
| Started | 9600 |
| Completed | 9600 |
| HTTP 200 | 9600 |
| Timeout | 0 |
| Connection error | 0 |
| Success rate | 100% |
| Timeout rate | 0% |
| Successful RPS | 160 |
| Total RPS | 160 |
| p50 | 13 ms |
| p95 | 187 ms |
| p99 | 774 ms |
| Max in-flight | 161 |

The registered classification is `STABLE`.

## Observer and runtime evidence

- Observer samples: 38
- Successful application samples: 38
- Successful mock samples: 38
- Readiness failures: 0
- Tomcat busy max: 135
- Tomcat queue max: 78
- HTTP active max: 47
- HTTP pending max: 0
- AI in-flight max: 3
- AI completed max observed: 9600
- Storage in-flight max: 0
- Storage completed max observed: 0

## Isolation conclusion

- T02 AI0 REAL with mock 4 CPU/1 GiB: `COLLAPSE`
- T02 AI0 SMALL with mock 4 CPU/1 GiB: `STABLE`
- `LARGE_PAYLOAD_INTERACTION_CONFIRMED=YES`
- `AI_CALL_ONLY_COLLAPSE_CONFIRMED=NO`
- `MOCK_CAPACITY_CONFOUNDER_CONFIRMED=NO`
- `MOCK_CAPACITY_EFFECT=MATERIAL`
- `FIRST_UNSTABLE_BOUNDARY=T02`
- `ROOT_CAUSE=DO_NOT_ASSERT_YET`

Under the fixed AI0 and expanded mock-capacity condition, replacing the REAL payload with the SMALL payload restored the run to STABLE. This supports a material interaction involving the larger payload and the AI path, but does not by itself identify Jackson, Base64, RestTemplate, or another specific root cause.

## Artifact locations

Run artifacts are under `experiment/results/MVC-DIAG-T02-AI0-SMALL-001/`. The run-specific capacity override, startup/runtime contracts, client process contract, observer summary/stream, container states, and mock metrics are preserved. Large raw client result/progress files remain local in the run directory.
