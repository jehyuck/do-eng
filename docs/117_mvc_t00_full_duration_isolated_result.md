# MVC T00 Full-Duration Isolated Result

## Execution

- HEAD: `e1a9a4274e9e4ebf1680aff4e0ceadec0b18f4f0`
- Project: `doeng-mvcdiag-t00-isolated-001`
- Run ID: `MVC-DIAG-T00-ISOLATED-001`
- Outer execution timeout: `300 seconds`
- Topology scope: T00 only; T01 and the full matrix were not executed.
- WebFlux: not executed.

## Contract and Runtime

- Mode: `INGRESS`
- Payload profile: `SMALL`
- Active users: `160`
- Interval: `1000ms`
- Duration: `60000ms`
- Request timeout: `10000ms`
- Target: `http://127.0.0.1:8002/experiment/mvc-probe`
- Fixture: `image\\arc.jpg`, 265,745 bytes, SHA-256 `1EEADB414471C8F89207118BAAD01D1A9EC7B05306DF0482A79D92D2C615FA99`
- Startup gate: `PASS`
- Runtime contract: `PASS`
- Container restart: `0`
- OOMKilled: `false`

## Process Evidence

- Node executable: `C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe`
- Node version: `v24.14.0`
- Client elapsed time: `60637ms`
- Progress at +5s: process running, progress present, 4 lines, result absent
- Progress at +30s: process running, progress present, 29 lines, result absent
- Progress at +55s: process running, progress present, 54 lines, result absent
- Final progress lines: `60`
- Final result file: present
- Client stdout bytes: `0`
- Client stderr bytes: `0`
- Recorded client process exit code: `null`

The client ran beyond the 60-second duration and produced a complete result, but
the temporary process wrapper did not record an explicit exit code. No second run
was made to repair that evidence gap.

## Client Result

- Started: `9600`
- Completed: `9600`
- HTTP 200: `9600`
- Timeout: `0`
- Connection error: `0`
- Success rate: `100%`
- p50: `9ms`
- p95: `95ms`
- p99: `590ms`
- Max in-flight: `160`

## Observer

- Observer exit code: `0`
- Observer samples: `34`
- Successful application samples: `34`
- Successful mock samples: `34`
- Readiness failures: `0`
- Tomcat busy max: `27`
- Tomcat queue max: `39`
- HTTP active max: `0`
- HTTP pending max: `0`
- AI in-flight max: `0`
- Storage in-flight max: `0`

## Validity and Classification

`T00_MEASUREMENT_VALID: NO`

The strict validity contract requires an explicit client process exit code of `0`.
Because the recorded value is `null`, this run is classified as:

`T00_CLASSIFICATION: INVALID`

This is not treated as an application performance failure. The client did not
terminate early, and the container remained healthy; the remaining issue is the
missing process-exit evidence.

`CLIENT_PROCESS_EARLY_TERMINATION: NO`

## Preserved Artifacts

- `experiment/results/MVC-DIAG-T00-ISOLATED-001/startup-gate.json`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/runtime-contract.json`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/client-process-contract.json`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/client-process.stdout.log`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/client-process.stderr.log`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/client-progress.jsonl`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/progress-checkpoints.json`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/client-results.json`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/observer.jsonl`
- `experiment/results/MVC-DIAG-T00-ISOLATED-001/observer.summary.json`

