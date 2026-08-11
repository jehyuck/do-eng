# MVC I1S-AI1S Phase Root-Cause Diagnostic — PHASE001

## Run and frozen inputs

- Run: `I1S-AI1S-MVC-PHASE001`
- HEAD: `c50353c5fb742ec19f3d10c85391e105f1e4cc6d`
- Config: `experiment/config/comparison-vu160-service-1s-ai1000ms.json`
- Implementation: MVC400
- No WebFlux, JFR, container monitor, tuning, or additional run was executed.

## Validity outcome

The workload and drain artifacts were produced, but the runner did not produce the required final verification and phase-capture artifacts before the runtime was removed. The run therefore cannot support a phase root-cause conclusion.

```text
EXECUTION_VALIDITY: INVALID
APPLICATION_LOG_CAPTURE: FAIL
PHASE_TRACE_PRESENT: NO
PHASE_TRACE_JSONL_VALID: NOT_AVAILABLE
PHASE_TRACE_COUNT: 0
ROOT_CAUSE_CONCLUSION: NOT_ALLOWED
```

## Available raw result

`client-results.json` reports 16,487 started and completed requests, 40 HTTP 200 responses, 16,447 client timeouts, zero connection errors, p50 9,174 ms, p95 9,974 ms, p99 10,012 ms, and max in-flight 1,600. These are preserved as observed values only; they are not interpreted as a phase-level cause because no phase trace was captured.

Available artifacts and SHA-256:

```text
experiment/results/I1S-AI1S-MVC-PHASE001/run-config.json
83D72F2E1E9DFB3CB5E246B12F4F1B30829ADCF79C04940A856F46478B0D39BC

experiment/results/I1S-AI1S-MVC-PHASE001/resolved-experiment-config.json
87197229E4191EA31642ADA19E0076A122AA17B84014EFDB07D4F7FCE8D1A27D

experiment/results/I1S-AI1S-MVC-PHASE001/client-results.json
6B7C0E23310DA3066A9B219A59DD7DF0E88C885D77D0EBB85221C2F5E94010F5

experiment/results/I1S-AI1S-MVC-PHASE001/mock-metrics-after.json
86B5DE848025A59D784120BC9E16C990008ECAE80162F5C929B1798D7EBC73C3
```

Missing from the preserved run directory are `verification-summary.json`, `application-container.log`, `mvc-phase-trace.jsonl`, and the final mission-completion artifact. Because the application container has already been removed, these missing artifacts cannot be recovered from this run.

## Required final classification

```text
EARLIEST_PRIMARY_DELAY: NOT_IDENTIFIED
TRIGGER: NOT_IDENTIFIED
AMPLIFIER: NOT_IDENTIFIED
FINAL_COLLAPSE_STATE: OBSERVED_TIMEOUT_DOMINANCE_ONLY
CURRENT_ROOT_CAUSE_CONFIDENCE: LOW
HISTORICAL_DISCREPANCY: STILL_UNEXPLAINED
```
