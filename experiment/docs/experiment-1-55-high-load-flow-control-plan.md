# Exp155 High-Load Flow-Control Comparison Plan

## 질문

동일한 high-load workload에서 provider pending/acquire 경계에 직접 요청을 맡기는 CONTROL, full-path admission으로 fail-fast하는 GATE, bounded Sink Dispatcher queue로 기다리게 하는 SINK 중 어느 경계가 관측 가능한 처리·실패·drain 결과를 만드는가?

## 고정 조건

- 200 active missions, staggered arrival, 1000 ms interval, 30 s duration
- AI mock 2000 ms / HTTP 200, storage mock 100 ms / HTTP 200
- client timeout 15000 ms, server global deadline 10000 ms where applicable
- application 2 CPU / 3 GiB, JVM `-Xms512m -Xmx2g -XX:+UseG1GC`, DB pool 10
- same `image/arc.jpg`, 265745 bytes, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- isolated provider mode; token 100/160, AI 400/640, storage 100/160; pending acquire timeout 10000 ms
- no pool, sink, admission, scheduler, retry, or timeout tuning during the campaign

## Cells

### CONTROL

Source `507e075016728daeaab75a51e7172577efe4c5ce`; admission OFF; sink OFF. This cell observes direct provider pending/acquire behavior.

### GATE

Source `507e075016728daeaab75a51e7172577efe4c5ce`; admission `FULL_PATH/ENFORCE/400`; sink OFF. This cell observes fail-fast admission behavior.

### SINK

Source `cf5b36ad38928d55eab131d1328dc85ccff0ad3b`; admission OFF; existing dispatcher settings unchanged: global deadline 10 s, TOKEN 100/200, AI 400/800, STORAGE 100/200.

## Pilot and execution order

Run one pilot per cell first: `CONTROL-PILOT`, `GATE-PILOT`, `SINK-PILOT`. A pilot validates fingerprints, collectors, pressure, admission/sink meters, DB integrity and drain; it is not included in the three-run aggregate. If CONTROL does not reproduce provider pressure, stop with `PRESSURE_NOT_REPRODUCED`.

If pilots pass, execute exactly:

```text
CONTROL-1, GATE-1, SINK-1,
SINK-2, GATE-2, CONTROL-2,
CONTROL-3, SINK-3, GATE-3
```

Each cell requires three valid runs. Invalid runs are preserved and replaced only within the same cell.

## Measurements

Client: attempts, completed, HTTP 200/500/503/504, timeout, connection/transport errors, successful RPS, success rate, p50/p95/p99/max, max in-flight.

Provider: configured limits, active/pending peaks and timeline, acquire timeout/error, pending-limit exception.

Admission (GATE): started/completed/rejected/cancelled/released/current/max observed and leak check. CONTROL/SINK must show OFF at runtime.

Sink (SINK): TOKEN/AI/STORAGE queue and active timelines and peaks, queue-wait p50/p95/p99, enqueued/dequeued/completed/failed/cancelled/deadline/full and `result_emission_failed` (or `METER_ABSENT`). Final queue and active must be zero.

Runtime/DB: application CPU/memory, GC where available, restart/OOM, downstream in-flight, duplicate completion/progress/picture integrity and DB errors.

## Validity and decision

Pressure, high latency, errors and backlog are system outcomes, not automatic invalidity. Invalidity is limited to missing load/result, fingerprint mismatch, health/restart/OOM, collector failure, accounting/DB failure or non-zero final queue/active for SINK.

`SINK_RECOVERY_BENEFIT` requires repeated pending/acquire failure reduction and repeated HTTP 200/successful-RPS improvement without material CPU/memory/tail harm. `SINK_STABILITY_ONLY` requires failure reduction without throughput improvement. Otherwise use `SINK_NO_CLEAR_BENEFIT`, `SINK_REGRESSION`, or `INCONCLUSIVE` when pressure or evidence is insufficient.

## Non-goals

No production Java change, pool or sink tuning, adaptive capacity, Base64 scheduler change, MVC comparison, or general WebFlux claim.
