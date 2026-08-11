# MVC I1S-AI1S JFR-Only Root-Cause Diagnostic

## Scope

Diagnostic run: `I1S-AI1S-MVC-JFR001`  
Implementation: MVC400  
Config: `experiment/config/comparison-vu160-service-1s-ai1000ms.json`  
Compose project: `doeng-i1s-ai1s-mvc-jfr001`

This run was intended to capture JVM Flight Recorder data without container/application polling. No WebFlux run, tuning, production code change, or additional workload was performed.

## Execution result

The runtime started and the client workload completed its accounting, but the runner failed while waiting for the JFR recording:

`JFR recording did not finish before its deadline`

The JFR command was issued at `2026-08-11T03:23:01.248Z`:

```text
jcmd 1 JFR.start name=doeng_I1S_AI1S_MVC_JFR001 settings=profile duration=110s filename=/tmp/I1S-AI1S-MVC-JFR001.jfr maxsize=64m
```

The runner then stopped and removed the containers. No `jvm-recording.jfr`, `jfr-summary.txt`, `jfr-validation.json`, `jfr-analysis.txt`, or `verification-summary.json` exists in the run directory. Consequently, the run is not valid for a JFR-based execution or root-cause conclusion.

```text
MVC_EXECUTION_VALIDITY: INVALID
JFR_CAPTURED: NO
JFR_VALIDATED: NO
RAW_JFR_SHA256: NOT_AVAILABLE
```

## Preserved client result

The raw client summary records:

```text
started: 16535
completed: 16535
timeout: 16535
connectionError: 0
successfulRequests: 0
successfulRps: 0
totalRps: 157.47619047619048
p50/p95/p99: NOT_AVAILABLE
maxInFlight: 1600
accounting.valid: true
```

Mock drain artifacts show that the request path reached the configured downstream mock during the run, including AI and storage activity. These artifacts are preserved locally under `experiment/results/I1S-AI1S-MVC-JFR001/`; they do not substitute for the missing JFR evidence.

## Root-cause conclusion

The missing JFR prevents attribution of CPU hot paths, Tomcat worker stack states, HTTP connection-acquire versus socket-response waits, allocation/GC call paths, and JDBC wait stacks. The existing metrics from the earlier diagnostic are not silently reused as a JFR result.

```text
TOP_CPU_HOT_PATHS: NOT_IDENTIFIED
DOMINANT_TOMCAT_THREAD_STATE: NOT_IDENTIFIED
DOMINANT_TOMCAT_STACK: NOT_IDENTIFIED
HTTP_POOL_WAIT_TYPE: NOT_SUPPORTED
GC_PRESSURE: UNKNOWN
ALLOCATION_HOT_PATH: NOT_IDENTIFIED
DATABASE_PRIMARY_CAUSE: UNKNOWN
TRIGGER: NOT_IDENTIFIED
AMPLIFIER: NOT_IDENTIFIED
FINAL_COLLAPSE_STATE: NOT_IDENTIFIED_FROM_JFR
CURRENT_PRIMARY_BOTTLENECK: NOT_IDENTIFIED
CURRENT_ROOT_CAUSE_CONFIDENCE: LOW
HISTORICAL_DISCREPANCY: STILL_UNEXPLAINED
```

The client timeouts are preserved as an observed result of this invalid diagnostic run, not as a JFR-supported causal conclusion. No automatic rerun was performed.

```text
TUNING_EXECUTED: NO
WEBFLUX_EXECUTED: NO
PRODUCTION_CODE_CHANGED: NO
PERFORMANCE_LOAD_EXECUTED: YES (single approved diagnostic run)
```
