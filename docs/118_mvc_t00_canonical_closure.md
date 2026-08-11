# MVC T00 Canonical Closure

## Execution

- HEAD: `6a1da7a7fcdb57c7d5ebc26abe1073d512749cd2`
- Execution ID: `MVC-DIAG-T00-CLOSURE-001`
- Scope: one T00 execution only
- T01: not executed
- Full matrix: not executed
- WebFlux: not executed
- Code/config changes: none

## Contract

- Mode: `INGRESS`
- Payload profile: `SMALL`
- Active users: `160`
- Interval: `1000ms`
- Duration: `60000ms`
- Request timeout: `10000ms`
- Target: `http://127.0.0.1:8002/experiment/mvc-probe`
- Fixture: `image\\arc.jpg`
- Runtime: CPU 2, memory 3GiB, Tomcat 400, HTTP connections 400, DB pool 10, Xms 512m, Xmx 2048m

## Gates

- STARTUP_GATE: `PASS`
- RUNTIME_CONTRACT: `PASS`
- Container restart: `0`
- OOMKilled: `false`
- Node exit code: `0`
- Result file: present
- Progress file: present, 60 lines

## Client Result

- Client elapsed time: `60430ms`
- Started: `9600`
- Completed: `9600`
- HTTP 200: `9600`
- Timeout: `0`
- Connection error: `0`
- Success rate: `100%`
- p50: `10ms`
- p95: `95ms`
- p99: `745ms`
- Max in-flight: `160`

## Observer

- Observer exit code: `0`
- Samples: `33`
- Successful application samples: `33`
- Successful mock samples: `33`
- Readiness failures: `0`
- Tomcat busy max: `99`
- Tomcat queue max: `0`
- HTTP active max: `0`
- HTTP pending max: `0`

## Validity and Classification

The required validity conditions all passed:

`T00_MEASUREMENT_VALID=YES`

Applying the preregistered classification:

`T00_CLASSIFICATION=STABLE`

The prior full-duration result remains preserved as:

`PREVIOUS_T00_RESULT=PROVISIONAL_STABLE / INVALID_EXIT_CODE_MISSING`

This closure establishes:

`T00_CANONICAL_STATE=STABLE`

No root-cause or framework-level claim is made by this closure.

## Preserved Artifacts

- `experiment/results/MVC-DIAG-T00-CLOSURE-001/startup-gate.json`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/runtime-contract.json`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/client-process-contract.json`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/client-process.stdout.log`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/client-process.stderr.log`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/observer.summary.json`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/client-results.json`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/client-progress.jsonl`
- `experiment/results/MVC-DIAG-T00-CLOSURE-001/observer.jsonl`

