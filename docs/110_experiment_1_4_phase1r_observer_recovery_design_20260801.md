# Experiment 1-4 Phase 1-R — Observer Recovery Design

## Selected architecture

The existing monitor remains a separate child process. Application snapshot
and Docker stats collection are retained. DB sampling changes from synchronous
`spawnSync` to asynchronous `spawn` with one non-overlapping command at a time.
If a command times out, it is killed, the sample is written as a failed row,
and the next scheduled sample can proceed.

## Sampling contract

- Measurement cadence remains one second for container/application observation.
- DB cadence remains the existing two seconds.
- DB command timeout is five seconds for this recovery contract.
- A timer tick never starts a second DB command while one is running.
- Each sample records scheduled/start/end time, duration, timeout, exit code,
  command arguments, parsed values and error text.
- Process crash, missing mandatory snapshots, coverage below 95%, or a maximum
  gap over five seconds remains invalid.

## Scope guard

Changed files are observer source, observer source test, wrapper-compatible
artifact fields and documentation only. Application controller/service,
full-path admission, HTTP pool, DB pool, mock delays, fixture, VU count,
pacing, timeout workload and accounting behavior are unchanged.
