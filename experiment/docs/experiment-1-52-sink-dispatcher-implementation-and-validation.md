# Experiment 1-52 — Stage-Isolated Sink Dispatcher

## Purpose

Replace implicit Reactor Netty provider pending as the primary waiting boundary with explicit, stage-isolated bounded dispatchers before TOKEN, AI, and STORAGE outbound subscription.

This branch is an intervention branch. The comparison baseline remains `experiment/exp151-admission-gate-capacity`.

## Branch and controlled change

- Baseline: `experiment/exp151-admission-gate-capacity`
- Intervention: `experiment/exp152-sink-dispatcher`
- Request order remains: TOKEN -> AI -> image decode -> STORAGE -> DB
- Existing whole-request admission gate remains in place.
- Existing isolated Reactor Netty providers remain in place.
- DB implementation and ordering are not changed.

## Dispatcher architecture

Each stage owns an independent instance of `AbstractSinkDispatcher<I, O>`:

- one long-lived `Sinks.Many`
- one bounded `ArrayBlockingQueue`
- one long-lived consumer subscription
- `flatMap` concurrency equal to the stage execution budget
- source prefetch fixed to `1`
- one `Sinks.One` per submitted request

Shared behavior:

- deadline check before enqueue
- deadline check before downstream invocation
- timeout using the remaining global deadline
- cancellation marker and dequeue-time skip
- work-level error isolation so one failure does not terminate the shared consumer
- queue rejection distinct from deadline expiration

## Initial configuration

```yaml
doeng:
  dispatcher:
    global-deadline: 10s
    token:
      concurrency: 100
      queue-capacity: 2000
    ai:
      concurrency: 400
      queue-capacity: 800
    storage:
      concurrency: 100
      queue-capacity: 200
```

The AI and STORAGE queue capacities are deliberately smaller than the earlier design draft because queued work retains Base64 image strings or decoded byte arrays. These values are initial experiment values, not optimal-capacity claims.

## HTTP outcomes

- bounded queue rejection: HTTP 503
- global deadline exhaustion: HTTP 504
- downstream WebClient status propagation: unchanged

## Metrics

Actuator exposes:

- `doeng.dispatcher.queue.depth`
- `doeng.dispatcher.active`
- `doeng.dispatcher.queue.wait`
- `doeng.dispatcher.events`

All meters include a `dispatcher` tag: `token`, `ai`, or `storage`.

Event details distinguish:

- enqueued
- dequeued
- completed
- failed
- rejected / queue_full
- cancelled
- deadline / phase
- result_emission_failed

## Required validation before load

Run from `backend/doEngGameFlux`:

```bash
./gradlew clean test --no-daemon
./gradlew bootJar --no-daemon
```

Required PASS tests include:

- configured concurrency is never exceeded
- bounded queue rejects overflow
- expired work does not invoke downstream
- remaining global deadline terminates execution
- cancelled queued work is skipped
- one work failure does not terminate the shared consumer
- stopped dispatcher rejects new work
- AI request identity headers survive the separate Sink consumer subscription
- queue rejection maps to 503
- deadline exhaustion maps to 504
- dispatcher gauges, timer, and counters are registered

## Smoke validation

Start the frozen experiment compose with the intervention JAR and verify:

1. application health is UP
2. pool mode is ISOLATED
3. provider budgets remain TOKEN 100 / AI 400 / STORAGE 100
4. dispatcher gauges exist for all three stages
5. queue depth and active return to zero after a single successful request
6. TOKEN -> AI -> STORAGE -> DB correlation remains intact
7. no dispatcher consumer termination log exists

## Load evidence

Capture both provider and dispatcher layers:

- provider active/pending peak by stage
- dispatcher active peak by stage
- dispatcher queue peak and queue-wait p50/p95/p99 by stage
- dispatcher rejected count
- deadline count by phase
- client HTTP 200/500/503/504 separately
- successful RPS and success rate
- latency p50/p95/p99
- application memory and GC
- DB integrity and duplicate-completion checks

## Interpretation

- Lower provider pending with growing dispatcher queue proves waiting moved to the explicit boundary; it does not by itself prove throughput improvement.
- A result that only converts timeout to 503/504 is stability protection, not successful-throughput improvement.
- Queue-capacity increases require retained-memory evidence. Do not increase AI or STORAGE queue capacity from pending peak alone.
- Do not call the initial queue capacities optimal.
