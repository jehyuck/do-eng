# MVC I1S-AI1S Saturation Onset Timeline Analysis

## Scope and disposition

This is a read-only analysis of the raw artifacts from `I1S-AI1S-MVC-DIAG001`. No workload was executed and no result, configuration, or source artifact was modified. Timeline offsets use measurement start (`T0`) from `client-summary.stdout.json`:

`T0 = 2026-08-11T02:46:01.467Z`.

The client run itself recorded 16,515 started and completed requests, 16,515 client timeouts, zero connection errors, zero HTTP 200/500/503 responses, and `maxInFlight=1601`. The monitor produced 107 application samples, 61 successful samples, and 46 application snapshot timeouts. No `verification-summary.json` or JFR recording/summary was produced because the monitor result was not sufficient for the normal verification path; this does not change the raw timeline below.

## First observations

| Signal | First observed threshold | Offset | Evidence |
|---|---:|---:|---|
| Docker CPU | >=100% and >=180% | T+1.796s | `container-stats.jsonl`, 204.47% |
| Application snapshot timeout | first timeout | T+2.038s | `container-monitor-summary.json` and application metrics |
| Client timeout | first completion timeout | T+10.022s | `client-summary.stdout.json`; request began at T+0.014s |
| Tomcat/request workers | busy >=300, >=350, and 400 | T+17.514s | `application-metrics.jsonl` |
| Tomcat/request queue | >0, >=100, and >=1000 | T+17.514s | `application-metrics.jsonl`, queue 2,162 at first threshold sample |
| Container memory | >=2048 MiB | T+21.796s | `container-stats.jsonl`, 2,050.048 MiB |
| Container memory | >=2560 MiB | T+28.797s | `container-stats.jsonl`, 2,628.608 MiB |
| Outbound HTTP leased | >=300 and >=350 | T+29.557s | `application-metrics.jsonl` |
| Container memory | >=2900 MiB | T+33.799s | `container-stats.jsonl`, 2,906.112 MiB |
| Outbound HTTP leased | 400 | T+36.019s | `application-metrics.jsonl` |
| Container memory | >=3000 MiB | T+36.796s | `container-stats.jsonl`, 3,006.464 MiB |

The maximum observed values were request-worker busy 400, request queue 7,792, outbound leased 400, container CPU 217.09%, and container memory 3,070.976 MiB against a 3 GiB limit. The queue maximum was recorded near `T+107.083s`, after the 105-second load interval while monitor sampling continued.

Outbound HTTP pending was never observed above zero. This means the application metric directly shows leased-pool saturation, but does not show a positive pending count in the sampled data.

## Saturation sequence

1. CPU crossed the observed 180% threshold at T+1.796s.
2. The first application snapshot timed out at T+2.038s. The nearest successful early samples still showed low worker occupancy and no outbound leased connections; therefore this monitor timeout is an observation failure, not proof that Tomcat saturation had already occurred.
3. The first client timeout completed at T+10.022s.
4. By T+17.514s, request workers were at 400 and the request queue was already 2,162, establishing the first direct application-side backlog signal.
5. Memory crossed 2,560 MiB at T+28.797s, followed by outbound leased connections crossing 300/350 at T+29.557s.
6. Memory crossed 2,900 MiB at T+33.799s; outbound leased reached 400 at T+36.019s; memory crossed 3,000 MiB at T+36.796s.
7. The request queue continued growing, reaching 7,792 in the post-load monitoring window.

Accordingly, `FIRST_OBSERVED_PRESSURE` is CPU, while the later collapse mechanism is coupled pressure across the Tomcat worker/request queue and outbound HTTP pool, with concurrent CPU and memory stress. The data does not isolate a unique single root cause.

## Monitor timeout position

`MONITOR_TIMEOUT_POSITION = BEFORE_SATURATION` when saturation means the first observed Tomcat queue/worker and outbound-pool thresholds. The first snapshot timeout was at T+2.038s, roughly 15.5 seconds before the first Tomcat queue/worker saturation sample. Snapshot failures continued during the later pressure period, so this ordering should not be read as evidence that the monitor endpoint caused the collapse.

## Database and downstream observations

Database pressure is not supported as the primary cause by the captured evidence:

- `Threads_connected` maximum: 11 at T+72.539s.
- `Threads_running` maximum: 2 at T+46.424s.
- Application database-pool maximum field: 10; active/pending values were not available in the application snapshot.

The mock drain summary recorded AI `maxInFlight=245`, AI completed 7,266 at load stop and 7,271 terminally; storage `maxInFlight=128`, storage completed 7,057 at load stop and 7,067 terminally. Drain completed with approximately 2,002 ms to zero for the reported terminal state. These values establish downstream activity and drain behavior but do not replace the application-side saturation signals.

## Historical comparison boundary

Established historical facts for `RUN-20260731-252` are limited to the previously recorded MVC400/VU160 result: interval 1,000 ms, AI delay 2,000 ms, 15,351 HTTP 200 responses, zero timeouts, p95 2,490 ms, p99 2,883 ms, and max in-flight 480. The historical artifact set available here does not provide a timestamp-aligned saturation timeline equivalent to this diagnostic, nor does it provide enough raw historical onset data to establish ordering of CPU, workers, HTTP pool, memory, or database signals.

Therefore the present timeline does not explain the historical discrepancy. It identifies a current coupled-pressure sequence only; it does not establish that the historical run had the same sequence or a different one.

## Final assessment

```text
FIRST_OBSERVED_PRESSURE: CPU
MONITOR_TIMEOUT_POSITION: BEFORE_SATURATION
DATABASE_PRIMARY_CAUSE: NOT_SUPPORTED
CURRENT_COLLAPSE_MECHANISM: coupled Tomcat worker saturation and outbound HTTP pool saturation, with CPU/memory stress; not uniquely isolated
HISTORICAL_DISCREPANCY_EXPLAINED: NO
ROOT_CAUSE_CONFIDENCE: MEDIUM
PERFORMANCE_LOAD_EXECUTED: NO
```

Raw artifacts remain under `experiment/results/I1S-AI1S-MVC-DIAG001/`; the prior artifact index is associated with commit `0fb17e4`. No result artifact was rewritten by this analysis.
