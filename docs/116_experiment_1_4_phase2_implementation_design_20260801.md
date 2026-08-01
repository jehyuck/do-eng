# Experiment 1-4 Phase 2 — Implementation Design

`AdmissionProperties.mode` selects `FULL_PATH` or `PER_OUTBOUND_CALL`.
Phase 1 defaults to `FULL_PATH`; Phase 2 enables only `PER_OUTBOUND_CALL`.
Both modes use the same CAS gate, shared budget 320 and zero-wait rejection.

The gate acquires lazily at subscription through `Mono.defer`. The supplier is
invoked only after acquisition. `doFinally` releases on complete, error and
cancellation exactly once. No blocking, queue, retry, fallback or detached
subscription is introduced.

Stage mapping: TOKEN is `TokenComponent.jwtConfirm`, AI is
`AiGameController.requestDecision`, and STORAGE is `MissionImageStorage.upload`.
Stage counters record acquired/rejected/released while aggregate counters
continue to enforce one shared 320 budget.
