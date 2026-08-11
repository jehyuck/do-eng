# MVC Diagnostic Matrix Execution Result

## Execution

HEAD: `150e5ee28e4f193ccfcc5e5831ac4e357f185937`

Execution status: `STOPPED_INVALID`

Image contract: `PASS`

- MVC image ID: `sha256:984fa39f3ab397d831086f8bef96402180c1d80d2d47b0a0274b2189652b6d4d`
- experiment-mock image ID: `sha256:0bbf354a08732a5dbfd3a3013218a6f1955d74c1bc41ecc407e819ba1788bbf6`

Runtime contract: `NOT_REACHED`

The runner built and pinned the images, then started the T00 Compose project. Before workload execution, the readiness helper invocation failed because the second `-ComposeFiles` value was consumed as the positional `MainPort` argument. The runner stopped at the startup gate and tore down the T00 project. No diagnostic request was sent.

## Topology Results

| Case | Mode | Success | Timeout | p50 | p95 | p99 | MaxInFlight | Classification |
|---|---|---:|---:|---:|---:|---:|---:|---|
| T00 | INGRESS / SMALL | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | NOT_MEASURED | INVALID_CONFIGURATION |
| T01 | INGRESS / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |
| T02 | AI / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |
| T03 | AI_DECODE / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |
| T04 | AI_STORAGE / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |
| T05 | TOKEN_AI_STORAGE / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |
| T06 | FULL / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |
| T07 | FULL_ORIGINAL_SCHEDULER / REAL | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED | NOT_EXECUTED |

## First Unstable Boundary

case: `NOT_REACHED`

mode: `NOT_REACHED`

previous stable case: `NOT_REACHED`

classification: `INVALID_CONFIGURATION`

## Boundary Observer

No boundary case executed.

Tomcat busy max: `NOT_MEASURED`

Tomcat queue max: `NOT_MEASURED`

HTTP active max: `NOT_MEASURED`

HTTP pending max: `NOT_MEASURED`

AI in-flight max: `NOT_MEASURED`

Storage in-flight max: `NOT_MEASURED`

Container restart: `0` at the pre-readiness capture

OOMKilled: `false` at the pre-readiness capture

Post-load idle: `NOT_REACHED`

Time-to-idle: `NOT_MEASURED`

## Boundary Matrix

B00–B09: `NOT_EXECUTED`

## Cold vs Warm

B00: `NOT_EXECUTED`

B01: `NOT_EXECUTED`

## AI Delay

B02–B05: `NOT_EXECUTED`

## Interval

B06–B08: `NOT_EXECUTED`

## Timeout

B00: `NOT_EXECUTED`

B09: `NOT_EXECUTED`

TIMEOUT_ROLE: `INCONCLUSIVE`

## Evidence Boundary

Confirmed:

- The requested HEAD matched exactly.
- Existing unrelated dirty changes were preserved.
- MVC and experiment-mock images were built and image IDs were resolved through `docker image inspect`.
- T00 containers were created and reached the pre-readiness capture with restart count 0 and OOMKilled false.
- The readiness helper failed before the workload because its `-ComposeFiles` argument vector was not preserved as a string array.
- T00 was torn down by the runner; no workload result or boundary result exists.
- `docs/113_mvc_diagnostic_matrix_result.md` was not modified.

Not established:

- MVC runtime contract pass/fail.
- Any topology performance result.
- Any boundary performance result.
- Any application bottleneck or root cause.

ROOT_CAUSE: `DO_NOT_ASSERT_YET`
