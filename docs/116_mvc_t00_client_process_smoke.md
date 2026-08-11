# MVC T00 Client Process Smoke

## Scope

This was a one-user, one-second client-process smoke for the existing T00
environment. No matrix topology, WebFlux workload, or performance comparison was
run. No source, configuration, or production logic was changed.

## Runtime

- Evidence HEAD before smoke: `af2e1f109399684f8c5501cfba5855b1981a2acf`
- Node executable: `C:\Users\KOSCOM\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe`
- Node version: `v24.14.0`
- Compose project: `doeng-mvcdiag-client-smoke`
- Locked MVC image: `sha256:edf0b39b32a6771edc24479b87a4ec273f7336a61aca08f837baaca6c34733e7`
- Startup gate: `PASS`
- Runtime contract: `PASS`
- Container restart count: `0`
- OOMKilled: `false`

Fixture:

- Path: `image\arc.jpg`
- Bytes: `265745`
- SHA-256: `1EEADB414471C8F89207118BAAD01D1A9EC7B05306DF0482A79D92D2C615FA99`

## Client Contract

- Script: `experiment\load\mvc-diagnostic-load.js`
- Mode: `INGRESS`
- Payload profile: `SMALL`
- Active users: `1`
- Interval: `1000ms`
- Duration: `1000ms`
- Request timeout: `10000ms`
- Target: `http://127.0.0.1:8002/experiment/mvc-probe`
- Run ID: `MVC-DIAG-CLIENT-SMOKE`

## Result

- Node exit code: `0`
- Progress file: present, 2 lines
- Result file: present
- Started: `2`
- Completed: `2`
- HTTP 200: `2`
- Timeout: `0`
- Client stdout bytes: `0`
- Client stderr bytes: `0`

## Classification

`CLIENT_PROCESS_SMOKE: PASS`

The client process ran to completion and wrote both progress and final result
artifacts. This confirms the client script can execute under the resolved Node
runtime; it does not constitute a performance measurement.

## Preserved Artifacts

- `experiment/results/MVC-DIAG-CLIENT-SMOKE/startup-gate.json`
- `experiment/results/MVC-DIAG-CLIENT-SMOKE/runtime-contract.json`
- `experiment/results/MVC-DIAG-CLIENT-SMOKE/client-process-contract.json`
- `experiment/results/MVC-DIAG-CLIENT-SMOKE/client-process.stdout.log`
- `experiment/results/MVC-DIAG-CLIENT-SMOKE/client-process.stderr.log`
- `experiment/results/MVC-DIAG-CLIENT-SMOKE/client-progress.jsonl`
- `experiment/results/MVC-DIAG-CLIENT-SMOKE/client-results.json`

