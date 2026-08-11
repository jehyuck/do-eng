# MVC I1S-AI1S Final Phase Diagnostic — PHASE002

## Run

- Run: `I1S-AI1S-MVC-PHASE002`
- HEAD: `c8cf9641e0b74b97b0d2ab92ddbba0c6e82bf566`
- Implementation: MVC400
- Config: `experiment/config/comparison-vu160-service-1s-ai1000ms.json`
- Observability: disabled; JFR and container monitor were not run.
- This was the single PHASE002 workload. No additional run was executed.

## Execution gate

```text
EXECUTION_VALIDITY: VALID
APPLICATION_OUTCOME: PASS
APPLICATION_LOG_CAPTURE: FAIL
PHASE_TRACE_PRESENT: NO
PHASE_TRACE_JSONL_VALID: NO
PHASE_TRACE_COUNT: 0
ROOT_CAUSE_CONCLUSION: NOT_ALLOWED
```

The execution and application accounting artifacts were produced and the runner reported `executionValidity=VALID`. However, the required phase-analysis artifacts were not produced. Both the normal capture and finally recovery attempted `docker logs`; PowerShell treated the native stderr line `Picked up JAVA_TOOL_OPTIONS: -Xms512m -Xmx2048m -XX:+UseG1GC` as the capture failure. The runner preserved that failure in `application-diagnostic-recovery-error.txt` and did not produce `application-container.log` or `mvc-phase-trace.jsonl`.

## Available workload result

From `experiment/results/I1S-AI1S-MVC-PHASE002/client-results.json`:

```text
started: 14854
completed: 14854
HTTP200: 14337
timeout: 517
connectionError: 0
p50: 1416 ms
p95: 9048 ms
p99: 9758 ms
maxInFlight: 1363
errorRate: 0.034805439612225667
```

These are preserved observations only. They are not attributed to a request phase because the phase trace is missing.

## Container state

`server-container-state.json` captured the MVC container as:

```text
status: running
running: true
exitCode: 0
oomKilled: false
restartCount: 0
nanoCpus: 2000000000
memory: 3221225472
```

No inference about admission, body processing, token, AI, storage, or DB phase latency is permitted from this run.

## Historical boundary

```text
HISTORICAL_DISCREPANCY: STILL_UNEXPLAINED
CURRENT_ROOT_CAUSE_CONFIDENCE: LOW
TUNING_EXECUTED: NO
WEBFLUX_EXECUTED: NO
HARD_STOP: PHASE002_IS_FINAL_DIAGNOSTIC
```
