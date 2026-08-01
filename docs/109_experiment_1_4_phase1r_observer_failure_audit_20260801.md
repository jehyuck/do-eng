# Experiment 1-4 Phase 1-R — Observer Failure Audit

## Direct source evidence

`experiment/scripts/monitor-containers.js` used `spawnSync("docker", ...)`
for every DB sample with a hard-coded one-second timeout. The call was made
from the monitor process's timer callback. The same observer used an async
`docker stats` stream and HTTP snapshots, so DB sampling was the blocking
boundary.

The affected raw rows in all three corrected BEFORE attempts contain:

```text
error: spawnSync docker ETIMEDOUT
```

Affected runs:

- `RUN-20260801-EXP14-BEFORE-001`: 41 DB monitor failures
- `RUN-20260801-EXP14-BEFORE-002`: 39 DB monitor failures
- `RUN-20260801-EXP14-BEFORE-003`: 21 DB monitor failures

## Classification

Primary: **O1 — synchronous child-process blocking**.

Contributing candidates: **O2 — per-sample Docker CLI churn**, **O4 — timeout
too short for the current host**, and **O5 — Docker daemon/CLI contention**.
The raw evidence does not isolate O4 from O5, so neither is claimed as the
sole cause.

Rejected as primary: application/business behavior, WebFlux chain ordering,
admission budget, pool configuration, DB application access and load
accounting. Those were unchanged and the client/accounting/correctness parts
of the runs completed successfully.

## Recovery decision

Use an observer-only asynchronous child-process call with a single in-flight
guard. Preserve command arguments, start/end timestamps, duration, exit code,
timeout flag, stderr and parsed values. A five-second command timeout is
explicitly recorded in the observer design; it does not alter application or
workload timeouts.
