# Experiment 1-4 Phase 1 — Corrected BEFORE Result

## Status

`NOT CLOSED — NO VALID CORE BASELINE`

The corrected load driver and accounting contract executed successfully at
the client level, but the required DB/container observer failed during each
200-VU core attempt. Per the frozen validity contract, these are not valid
measurement runs and cannot form the three-run BEFORE cohort.

## Preserved core attempts

| Run | Client accounting | DB monitor failures | Measurement validity |
|---|---|---:|---|
| RUN-20260801-EXP14-BEFORE-001 | equations passed; raw preserved | 41 | INVALID |
| RUN-20260801-EXP14-BEFORE-002 | equations passed; raw preserved | 39 | INVALID |
| RUN-20260801-EXP14-BEFORE-003 | equations passed; raw preserved | 21 | INVALID |

The failure was `spawnSync docker ETIMEDOUT` in the existing database monitor.
The client raw files still contain the corrected outcome categories and
accepted-only latency populations where accepted responses existed. Because
the observer contract failed, these values are diagnostic observations only,
not a baseline aggregate.

## Scout

`RUN-20260801-EXP14-SCOUT-003` demonstrated a VALID corrected 20-VU warm-up
and a client-valid 200-VU path, but it was likewise marked diagnostic/invalid
because the DB monitor recorded 21 collection failures. Earlier `SCOUT-001`
stopped before load at the health gate; `SCOUT-002` stopped at warm-up
correctness after an insufficient low-duration drain. All raw artifacts are
preserved.

## Interpretation boundary

This does not prove a WebFlux business-path failure or a corrected throughput
claim. It proves that the current frozen observer contract cannot produce a
valid 200-VU corrected baseline on this host when the DB monitor's one-second
Docker command timeout is exceeded.
