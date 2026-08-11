# MVC Diagnostic Matrix Valid Execution Result

## Execution

- HEAD: `7ef7cce1f4d011e87c1d4a370c53bda355779922`
- Execution status: `STOPPED_INVALID`
- Attempt: one runner invocation, started once
- Image contract: `PASS`
- Runtime contract: `PASS` for T00
- Performance measurement validity: `NOT_ESTABLISHED`

The runner reached T00 startup and observer capture, but no T00 `client-results.json`
was produced. The runner therefore stopped while classifying T00, before T01 and
before any boundary case. This is preserved as an invalid harness execution, not as
a performance classification.

## Topology Results

| Case | Mode | Success | Timeout | p50 | p95 | p99 | MaxInFlight | Classification |
|---|---|---:|---:|---:|---:|---:|---:|---|
| T00 | INGRESS | NOT_CAPTURED | NOT_CAPTURED | NOT_CAPTURED | NOT_CAPTURED | NOT_CAPTURED | NOT_CAPTURED | STOPPED_INVALID: client result missing |
| T01 | NOT_EXECUTED | | | | | | | |
| T02 | NOT_EXECUTED | | | | | | | |
| T03 | NOT_EXECUTED | | | | | | | |
| T04 | NOT_EXECUTED | | | | | | | |
| T05 | NOT_EXECUTED | | | | | | | |
| T06 | NOT_EXECUTED | | | | | | | |
| T07 | NOT_EXECUTED | | | | | | | |

## First Unstable Boundary

- case: `NOT_ESTABLISHED`
- mode: `NOT_ESTABLISHED`
- previous stable case: `NOT_ESTABLISHED`
- classification: `STOPPED_INVALID`
- reason: T00 result artifact was absent; no application outcome was classified.

## Boundary Observer

T00 observer captured 2 samples. The observed maxima were:

- Tomcat busy max: `0`
- Tomcat queue max: `0`
- HTTP active max: `0`
- HTTP pending max: `0`
- AI in-flight max: `0`
- Storage in-flight max: `0`
- container restart count: `0`
- OOMKilled: `false`

The T00 startup gate was PASS with a 10-second stable window. The T00 runtime
contract was PASS, with MVC image ID
`sha256:edf0b39b32a6771edc24479b87a4ec273f7336a61aca08f837baaca6c34733e7`.

## Boundary Matrix

Not executed. The topology stopped before a valid boundary target was established.

## Cold vs Warm

Not measured.

## AI Delay

Not measured.

## Interval

Not measured.

## Timeout

Not measured.

TIMEOUT_ROLE: `NOT_ESTABLISHED`

## Evidence Boundary

Confirmed:

- The specified runner was invoked once at the requested HEAD.
- T00 Compose startup, health/readiness parsing, runtime contract, and observer capture completed.
- T00 had no client result artifact, so the workload result could not be classified.
- T01–T07 and B00–B09 were not executed.
- No WebFlux workload was executed.

Not established:

- Any STABLE, DEGRADED, or COLLAPSE classification.
- A first unstable boundary.
- Any root cause.

ROOT_CAUSE: `DO_NOT_ASSERT_YET`

## Artifact Paths

- `experiment/results/MVC-DIAG-T00/startup-gate.json`
- `experiment/results/MVC-DIAG-T00/runtime-contract.json`
- `experiment/results/MVC-DIAG-T00/observer.jsonl`
- `experiment/results/MVC-DIAG-T00/container-state.json`
- `experiment/results/MVC-DIAG-T00/mock-metrics-final.json`
- `experiment/results/MVC-DIAG-T00/application-container.stdout.log`
- `experiment/results/MVC-DIAG-T00/application-container.stderr.log`
- `experiment/results/matrix-image-contract.json`
