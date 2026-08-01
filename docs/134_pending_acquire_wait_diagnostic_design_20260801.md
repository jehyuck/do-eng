# Experiment 1-7 - Connection Pending-Acquire Wait Diagnostic Design

## Decision

The prior Experiment 1-6 decision remains **B - instrumentation insufficient**.
The present diagnostic does not change that classification in advance and does
not tune the application.

## Why this metric

AI500 repeated higher pool pending, TOKEN/STORAGE mean duration, and accepted
tail latency, but the existing endpoint discarded the
`reactor.netty.connection.provider.pending.connections.time` Timer by reading
only Gauges. Full-path permit holding was not measured either. The least
ambiguous single addition for the stated question is the Reactor Netty
pending-acquire Timer, because it directly measures time waiting for a shared
outbound connection.

## Observation-only change

`DiagnosticPoolEndpoint` now reads Gauge meters as before and Timer meters via
Micrometer `Timer` APIs. It returns count, totalTimeMs, meanMs, maxMs,
percentiles when published, and tags. If the runtime registry has no Timer or
no percentiles, the artifact preserves an empty result/`NOT AVAILABLE` rather
than manufacturing values. No publisher, permit, pool, timeout, workload, or
business behavior is changed.

## Frozen conditions

FULL_PATH, permit 320, HTTP pool 400, DB pool 10, application 2 CPU/3 GiB,
VU200, 105 s, one-second pacing, storage 100 ms, client timeout 10 s, same
fixture/auth/payload/completion semantics, fresh JVM, corrected accounting,
recovered observer, JFR OFF, continuous snapshots OFF, DB/container monitoring
ON, load-stop snapshot ON, 30 s drain ON. Only the synthetic AI delay differs:
AI1000 versus AI500.

## Diagnostic pair

- `RUN-20260801-EXP17-AI1000-DIAG-001`
- `RUN-20260801-EXP17-AI500-DIAG-001`

AI1000 runs first. This is one diagnostic pair, not a new core cohort. Only
configuration/collector/instrumentation failure may trigger one same-arm
replacement; performance outcomes remain valid system outcomes.

## Evidence and decision

Collect existing client, stage, pool, admission, resource, correctness, and
drain evidence plus the new Timer fields. Supported connection-wait evidence
requires AI500 pending count and Timer mean/p95/p99 to all exceed AI1000 while
the prior pressure direction remains consistent. If the Timer is absent or the
comparison does not support that relationship, classify the diagnostic as B or
F as specified by the execution prompt. No automatic remediation follows.

## Hard stop

After the pair, do not change permits, pool, timeout, VU, resources, AI delay,
queue policy, application code, or MVC comparison. At most one application-side
remediation design may be proposed only if the Timer directly supports the
connection-wait mechanism; it must not be implemented in this task.
