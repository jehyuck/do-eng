# MVC M001 Request Phase Timing Correlation Audit

## Scope

This is a static audit of the canonical current MVC run `I1S-AI1S-M001`. No workload, application, mock, database, JFR capture, or instrumentation was started. No raw result artifact was modified.

The source lock is the canonical pair index `experiment/results/I1S-AI1S-PAIR001-artifact-index.json` and the run directory `experiment/results/I1S-AI1S-M001/**`. Other diagnostic/JFR runs and historical RUN-252 phase timing are excluded.

## Artifact inventory and correlation

The expected artifacts are present: `client-results.json`, `client-progress.jsonl`, `mock-requests.json`, `mock-metrics-after.json`, `load-stop-mock-metrics.json`, `mock-drain.jsonl`, `mock-drain-summary.json`, `storage-before.json`, `storage-after.json`, `mission-completions.json`, `db-before.json`, `db-after.json`, and `verification-summary.json`.

`client-results.json` contains 16,464 request records with `requestId`, `missionRunId`, `requestStartedAt`, and `completedAt`. The mock request artifact contains 44,409 aggregate request events, but every inspected event has `experimentRunId=null` and `experimentRequestId=null`. It records only `observedAt`, method, path, and content length. Therefore client requests cannot be joined to individual mock arrivals or completions by request ID.

The available correlation is:

- client request ↔ mission completion: `missionRunId` is present and usable;
- client request ↔ mock request: unavailable;
- storage object ↔ mission completion: object keys exist in the separate artifacts, but no client request ID is preserved in the mock event stream.

## First ten seconds

The progress sample at `2026-08-11T02:22:55.754Z`, the first recorded sample at or after T+10 seconds from client start `2026-08-11T02:22:45.679Z`, reports:

| Signal | Count |
|---|---:|
| Client requests started | 1,441 |
| Client requests completed | 4 |
| In flight | 1,437 |
| Active users | 160 |
| Token verification mock arrivals (`GET /api/member/ai`) | 336 |
| AI mock arrivals (`POST /analyze/face`) | 24 |
| Storage mock arrivals (`PUT /storage/object`) | 0 |
| Mission completion records | 0 |

The mock arrival counts use the same sample boundary. They are aggregate path counts, not per-client phase transitions.

The full mock chronology begins with token verification at `02:22:48.655Z` (T+2.976s), AI arrivals at `02:22:49.544Z` (T+3.865s), and storage arrivals at `02:22:56.138Z` (T+10.459s). Mock arrivals continue through approximately `02:24:48Z`, well after the client load stopped at `02:24:30.689Z`.

## Client deadlines and downstream chronology

The client request timeout is 10,000 ms. The 16,404 timeout records are `AbortError` records with client-deadline transport classification. The 60 HTTP 200 records have latency p50 9,161 ms, p95 9,959 ms, p99 9,998 ms, and maximum 9,998 ms.

Exact `AI_BEFORE_CLIENT_DEADLINE`, `AI_AFTER_CLIENT_DEADLINE`, `STORAGE_BEFORE_CLIENT_DEADLINE`, and `STORAGE_AFTER_CLIENT_DEADLINE` counts cannot be computed because mock arrivals have no request correlation key and no mock completion timestamp. The run-level facts are narrower:

- AI arrivals were observed before the first ten-second sample boundary.
- No storage arrival was observed by that boundary; the first storage arrival was at T+10.459s.
- Downstream arrivals and completions continued after client timeouts and after load stop.

The 60 HTTP 200 request records all have a matching `missionRunId` in `mission-completions.json`. There are 210 mission completion records in total. The client and mission timestamps show the successful cohort reaching database completion before its HTTP response: for example, `I1S-AI1S-M001-u37-m1` has DB `completedAt` `02:22:57.560Z` and client completion `02:22:58.168Z`. The remaining completion records cannot be assigned to an individual mock phase or exact client deadline because the request stream contains repeated mission identifiers across attempts and the mock stream lacks request IDs.

The completion count therefore has mixed meaning: some work completed before an observed HTTP 200, while other downstream work completed after client timeout or during drain. Counts alone do not prove that all downstream work completed before or after the client deadline.

## Server work after client abort

`SERVER_WORK_CONTINUES_AFTER_CLIENT_ABORT` is **SUPPORTED at run level, not per-request level**. Evidence includes:

- timeout requests begin at `02:22:45.684Z`;
- mock arrivals continue until about `02:24:48Z`;
- `mock-metrics-after.json` reports `aiCompleted=16464` and `storageCompleted=16464`;
- at load stop, AI and storage work remained in flight (`aiInFlight=149`, `storageInFlight=32`), and the 15-second drain ended with residual backlog (`aiInFlight=234`, `storageInFlight=93`).

This establishes continued downstream activity after client deadline events at run level. It does not establish which timed-out request produced any particular downstream event.

## Mission completion timestamp semantics

The MVC source sets `LocalDateTime completedAt = LocalDateTime.now()` before the `INSERT IGNORE` and subsequent picture/progress statements in `backend/doEngGameMvc/src/main/java/com/example/doenggamemvc/service/MissionDatabaseService.java:29-55`. The method is transactional, but `completedAt` is assigned before those database operations; it is not a recorded transaction-commit timestamp. Consequently, the mission completion timestamp supports chronology around the application’s completion transaction path, but cannot independently prove transaction end time.

## HTTP 200 cohort

The HTTP 200 cohort is 60 requests, with start times from `02:22:48.353Z` to `02:23:06.037Z` and client completion times from `02:22:58.168Z` to `02:23:14.969Z`. All 60 have a matching mission completion record by `missionRunId`. The cohort is therefore not confined to the first ten seconds and is not evidence that the full request population reached the same phase.

## Phase localization conclusion

The earliest delay location is **NOT_IDENTIFIED**. The first-ten-second path counts show a large client-side in-flight population, token arrivals exceeding AI arrivals, no storage arrivals at the boundary, and no mission completions. Without per-request mock correlation and mock completion timestamps, the evidence cannot distinguish among token-to-AI admission, AI wait, AI-to-storage, storage wait, storage-to-DB, DB, or post-DB response delay.

The evidence supports continued downstream work and backlog after client abort, but does not localize a single primary phase or establish a DB-specific primary delay.

```text
AUDIT:
MVC_M001_REQUEST_PHASE_TIMING

SOURCE_LOCK:
PASS

PHASE_TIMING_EVIDENCE_SUFFICIENT:
NO

CORRELATION_KEY:
PARTIAL (client requestId/missionRunId; mock request correlation absent)

FIRST_10S_CLIENT_STARTED:
1441

FIRST_10S_CLIENT_COMPLETED:
4

FIRST_10S_TOKEN_EVENTS:
336

FIRST_10S_AI_EVENTS:
24

FIRST_10S_STORAGE_EVENTS:
0

FIRST_10S_MISSION_COMPLETIONS:
0

AI_BEFORE_CLIENT_DEADLINE:
NOT_IDENTIFIED (aggregate mock events; no request correlation)

AI_AFTER_CLIENT_DEADLINE:
NOT_IDENTIFIED (aggregate mock events; no request correlation)

STORAGE_BEFORE_CLIENT_DEADLINE:
NOT_IDENTIFIED (0 observed by first T+10.075s sample, but no per-request deadline join)

STORAGE_AFTER_CLIENT_DEADLINE:
NOT_IDENTIFIED (aggregate mock events; no request correlation)

HTTP200_COHORT_PATTERN:
60 HTTP 200 responses; all 60 have matching mission completion records; p50/p95/p99 latency 9161/9959/9998 ms

SERVER_WORK_CONTINUES_AFTER_CLIENT_ABORT:
SUPPORTED (run-level; per-request attribution unavailable)

DOWNSTREAM_COMPLETION_COUNT_MEANING:
MIXED

EARLIEST_DELAY_LOCATION:
NOT_IDENTIFIED

DB_PRIMARY_DELAY:
NOT_SUPPORTED

CURRENT_ROOT_CAUSE_LOCALIZATION:
Downstream work and residual backlog continued after client deadlines, but the earliest or primary phase is not localized by the preserved artifacts.

PERFORMANCE_LOAD_EXECUTED:
NO

PRODUCTION_CODE_CHANGED:
NO
```
