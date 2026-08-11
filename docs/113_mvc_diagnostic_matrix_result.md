# MVC Diagnostic Matrix Result

## Execution

HEAD: `df9a56c7243a37f289c9d29920a2555a0a435f11`

Matrix execution: `STOPPED_INVALID`

The runner stopped before T00 workload startup. MVC and experiment-mock image builds completed, but the runner could not resolve image IDs with `docker compose images -q` in the build-only project, which had no created containers. No application runtime was started and no workload request was sent.

Runtime contract: `NOT_REACHED`

Image contract: `FAIL — image build completed, ID resolution failed`

Built image outputs observed locally:

- MVC image: `doeng-mvcdiag-image-contract-mvc:latest`, `sha256:3d865f6e54521d84abada65c1e60c0787b14992d096a918fb514eee10519ba5a`
- experiment-mock image: `doeng-mvcdiag-image-contract-experiment-mock:latest`, `sha256:35cc9d7e07b5d5223a74373f3e4bd513b99426b8c17f4c720ebb52bd95bfc285`

Plan artifact: `experiment/results/MVC-DIAG-matrix-plan.json` (`executed: false`)

## Topology

No topology case executed. T00–T07 are `NOT_EXECUTED`.

## First Unstable Boundary

case: `NOT_REACHED`

mode: `NOT_REACHED`

previous stable case: `NOT_REACHED`

classification: `INVALID_CONFIGURATION`

## Observer at Boundary

No application container was started; observer and runtime metrics were not collected.

Tomcat busy max: `NOT_MEASURED`

Tomcat queue max: `NOT_MEASURED`

HTTP active/leased max: `NOT_MEASURED`

HTTP pending max: `NOT_MEASURED`

AI in-flight max: `NOT_MEASURED`

Storage in-flight max: `NOT_MEASURED`

readiness failures: `NOT_REACHED`

container restart: `NOT_REACHED`

OOMKilled: `NOT_REACHED`

post-load idle: `NOT_REACHED`

## Boundary Matrix

No boundary case executed. B00–B09 are `NOT_EXECUTED`.

## Cold vs Warm

B00: `NOT_EXECUTED`

B01: `NOT_EXECUTED`

Difference: `NOT_MEASURED`

## AI Wait Sensitivity

B02: `NOT_EXECUTED`

B03: `NOT_EXECUTED`

B04: `NOT_EXECUTED`

B05: `NOT_EXECUTED`

## Interval Sensitivity

B06: `NOT_EXECUTED`

B07: `NOT_EXECUTED`

B08: `NOT_EXECUTED`

## Timeout Amplifier

B00 10s: `NOT_EXECUTED`

B09 30s: `NOT_EXECUTED`

TIMEOUT_ROLE: `INCONCLUSIVE`

## Evidence Boundary

Facts observed:

- The requested HEAD was checked and matched.
- Existing unrelated dirty files were preserved.
- MVC and experiment-mock image builds completed successfully.
- `docker compose images -q` returned no IDs for the build-only project because it had no containers.
- The runner stopped before runtime startup and before any performance workload.

Not established:

- MVC processing boundary.
- Runtime contract validity.
- Topology or boundary performance results.
- Any application root cause.

No causal conclusion is asserted.
