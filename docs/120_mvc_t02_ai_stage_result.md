# MVC T02 AI Stage Result

## Execution

- HEAD: `440cfce376aad38e1bbba47277d3b4f162e26cdf`
- Execution ID: `MVC-DIAG-T02-CLOSURE-001`
- T00 canonical state: `STABLE`
- T01 canonical state: `STABLE`
- T03 and later cases: not executed
- Boundary matrix: not executed
- WebFlux: not executed
- Code/config changes: none

## Contract

- Mode: `AI`
- Payload profile: `REAL`
- Active users: `160`
- Interval: `1000ms`
- Duration: `60000ms`
- Request timeout: `10000ms`
- AI delay: `1000ms`
- Storage delay: `100ms`
- Target: `http://127.0.0.1:8002/experiment/mvc-probe`
- Fixture bytes: `265745`
- Fixture SHA-256: `1EEADB414471C8F89207118BAAD01D1A9EC7B05306DF0482A79D92D2C615FA99`
- Request JSON bytes: `354363`

## Gates

- STARTUP_GATE: `PASS`
- RUNTIME_CONTRACT: `PASS`
- Node exit code: `0`
- Result file: present
- Progress file: present, 56 lines
- Container restart: `0`
- OOMKilled: `false`
- Observer valid: `true`

## Client Result

- Client elapsed time: `71128ms`
- Started: `9105`
- Completed: `9105`
- HTTP 200: `35`
- Timeout: `9070`
- Connection error: `0`
- Success rate: `0.3844%`
- Timeout rate: `99.6156%`
- p50: `10049ms`
- p95: `10154ms`
- p99: `10207ms`
- Max in-flight: `1578`

## Observer

- Observer exit code: `0`
- Samples: `17`
- Successful application samples: `14`
- Successful mock samples: `5`
- Observer readiness failures: `17`
- Observer valid: `true`
- Tomcat busy max: `400`
- Tomcat queue max: `6544`
- HTTP active max: `400`
- HTTP pending max: `0`
- AI in-flight max: `75`
- AI completed observed max: `165`
- Storage in-flight max: `0`
- Storage completed observed max: `0`

The final direct mock metrics request was unavailable after the run and is
preserved as an artifact-level observation. The observer summary remained
`observerValid=true`; this does not alter the client validity gate.

## T01/T02 Contract Parity

`T01_T02_CONTRACT_PARITY=PASS` for the controlled fields:

- REAL payload, 160 users, 1000ms interval, 60000ms duration, 10000ms timeout,
  target, fixture, and application resource contract were unchanged.
- The intended changes were `MODE: INGRESS → AI` and `AI_DELAY_MS: 0 → 1000`.

## Validity and Classification

All required validity conditions passed:

`T02_MEASUREMENT_VALID=YES`

Applying the preregistered classification:

`T02_CLASSIFICATION=COLLAPSE`

because success was below 80% and timeout rate was at least 20%.

- Previous stable case: `T01`
- First unstable boundary: `T02`
- Boundary mode: `AI_REAL`
- Root cause: `DO_NOT_ASSERT_YET`

This result does not assert RestTemplate, blocking I/O, Tomcat exhaustion, or
AI delay as root cause. T03 and further runs were not executed.

## Preserved Artifacts

- `experiment/results/MVC-DIAG-T02-CLOSURE-001/startup-gate.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/runtime-contract.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/client-process-contract.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/client-process.stdout.log`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/client-process.stderr.log`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/observer.summary.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/mock-metrics-final.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/container-state.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/client-results.json`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/client-progress.jsonl`
- `experiment/results/MVC-DIAG-T02-CLOSURE-001/observer.jsonl`

