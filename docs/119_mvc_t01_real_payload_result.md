# MVC T01 REAL Payload Result

## Execution

- HEAD: `0e57bf14cd5ec34b8d0e31288160c1a41ee64ccb`
- Execution ID: `MVC-DIAG-T01-CLOSURE-001`
- T00 canonical state before execution: `STABLE`
- T02 and later cases: not executed
- Full matrix: not executed
- WebFlux: not executed
- Code/config changes: none

## Contract

- Mode: `INGRESS`
- Payload profile: `REAL`
- Active users: `160`
- Interval: `1000ms`
- Duration: `60000ms`
- Request timeout: `10000ms`
- Target: `http://127.0.0.1:8002/experiment/mvc-probe`
- Fixture: `image\\arc.jpg`
- Fixture bytes: `265745`
- Fixture SHA-256: `1EEADB414471C8F89207118BAAD01D1A9EC7B05306DF0482A79D92D2C615FA99`
- Request JSON bytes: `354363`

## Gates

- STARTUP_GATE: `PASS`
- RUNTIME_CONTRACT: `PASS`
- Node exit code: `0`
- Result file: present
- Progress file: present, 59 lines
- Container restart: `0`
- OOMKilled: `false`
- Observer valid: `true`

## Client Result

- Client elapsed time: `60784ms`
- Started: `9573`
- Completed: `9573`
- HTTP 200: `9572`
- Timeout: `8`
- Connection error: `0`
- Success rate: `99.9896%`
- p50: `29ms`
- p95: `4104ms`
- p99: `5981ms`
- Max in-flight: `685`

## Observer

- Observer exit code: `0`
- Samples: `31`
- Successful application samples: `31`
- Successful mock samples: `31`
- Readiness failures: `3`
- Tomcat busy max: `198`
- Tomcat queue max: `189`
- HTTP active max: `0`
- HTTP pending max: `0`

The observer summary reports `observerValid=true`; readiness failure count is
preserved as an observed metric and is not reclassified here.

## T00/T01 Contract Parity

`T00_T01_CONTRACT_PARITY=PASS` for the controlled fields:

- Mode, active users, interval, duration, request timeout, and target URL are equal.
- The only workload contract change is `PAYLOAD_PROFILE: SMALL → REAL`.
- REAL payload binary size is `265745` bytes and its SHA-256 matches the fixture.

## Validity and Classification

All required validity conditions passed:

`T01_MEASUREMENT_VALID=YES`

Applying the preregistered classification:

`T01_CLASSIFICATION=STABLE`

because success was at least 95% and timeout rate was below 5%.

- Previous stable case: `T00`
- First unstable boundary: `NOT_YET_REACHED`
- Root cause: `DO_NOT_ASSERT_YET`

This result does not authorize T02 or any additional run.

## Preserved Artifacts

- `experiment/results/MVC-DIAG-T01-CLOSURE-001/startup-gate.json`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/runtime-contract.json`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/client-process-contract.json`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/client-process.stdout.log`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/client-process.stderr.log`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/observer.summary.json`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/client-results.json`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/client-progress.jsonl`
- `experiment/results/MVC-DIAG-T01-CLOSURE-001/observer.jsonl`

