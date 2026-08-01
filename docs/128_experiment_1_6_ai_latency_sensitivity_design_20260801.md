# Experiment 1-6 - AI Service-Time Sensitivity Design

## Purpose

Test whether changing only synthetic AI mock response delay changes full-path
permit occupancy and usable capacity under the fixed 320-permit workload.
This is a synthetic dependency-latency sensitivity test, not a production AI
optimization or a WebFlux-versus-MVC comparison.

## Arms

| Arm | Admission | Permit | AI delay | Storage delay |
|---|---|---:|---:|---:|
| Baseline | FULL_PATH | 320 | 2,000 ms | 100 ms |
| AI1000 | FULL_PATH | 320 | 1,000 ms | 100 ms |
| AI500 | FULL_PATH | 320 | 500 ms | 100 ms |

AI1000 is completed before AI500 is interpreted. No 250 ms or other delay is
authorized.

## Frozen conditions

Pool 400, DB pool 10, application 2 CPU/3 GiB, VU200, 105 s, one-second
pacing, 10 s client timeout, same endpoint/fixture/payload/auth/scene/answer,
same completion semantics, fresh JVM, FULL_PATH outer gate ON, per-outbound
gates OFF, zero-wait fail-fast, corrected accounting, recovered observer,
JFR OFF, continuous comprehensive snapshots OFF, DB/container monitoring ON,
load-stop snapshot ON, 30 s drain ON. No application, pool, permit, timeout,
workload, storage, DB, scheduler, retry, fallback, or MVC changes.

## Research question

Under these fixed conditions, does reducing only AI mock delay from 2,000 ms to
1,000 ms and 500 ms reduce full-path permit holding time, increase successful
HTTP200 throughput, and reduce controlled 503 rate?

## Interpretation guard

The Little's Law calculation `320 / 112.7429 ≈ 2.84 s` is a heuristic only.
It must not be treated as a measured service time or as a prediction that
AI1000 will produce 174 RPS or AI500 239 RPS.

## Validity and safety

Each arm requires one valid scout and three VALID core runs. Measurement
invalidity is limited to config/fingerprint, observer/accounting/artifact,
fixture, fresh-JVM, or load-generator-contract failures. Low throughput,
503, latency, HTTP500, timeout, connection error, pool exception, drain or
resource saturation remain system outcomes; safety failure affects result
classification rather than silently removing a run.

Safety: HTTP500=0, pool exception=0, permit leak=0, max permit<=320,
acquired=released after drain, controlled503 no-side-effect PASS,
DB/storage consistency PASS, drain<=30 s, observer PASS, no generator
saturation.

## Quantitative criteria

Meaningful AI1000 improvement uses the frozen baseline thresholds:
successful RPS median >=124.0172, controlled503 median <=37.689%, accepted
p95 median <=4,263.6 ms, plus safety PASS.

Monotonic sensitivity is supported only if:

`AI500 successful RPS > AI1000 successful RPS > AI2000 baseline`,
`AI500 503 < AI1000 503 < AI2000 baseline`, and AI500 mean AI stage duration
is below AI1000. Completed throughput is reference-only because controlled
rejections can inflate it.

## Execution order

Scout AI1000, scout AI500, then crossover core order:
AI1000-001, AI500-001, AI1000-002, AI500-002, AI1000-003, AI500-003.
One same-arm replacement is allowed for an INVALID run; after three VALID
runs per arm, no further run is authorized.

## Classification and claim boundary

A: AI service time is a dominant capacity driver; B: partial effect; C: not
dominant; D: safety regression; F: inconclusive. A may support only that AI
dependency latency affected this fixed synthetic workload. It cannot support
claims about production AI, optimal 500 ms, WebFlux general performance, or
MVC superiority.
