# Experiment 1-4 Phase 2 — Source Audit

## BEFORE outcome errata

Raw `experiment/results/RUN-20260801-EXP14R-BEFORE-003/client-results.json`
classifies the one uncontrolled client outcome as `HTTP_500_UNCONTROLLED=0`
and `CLIENT_TIMEOUT=1`. The earlier “HTTP500=1” wording is corrected by this
addendum; no raw artifact is changed.

## Current lifecycle

`AiGameController` currently applies `AiOutboundAdmissionGate.execute` around
the complete token→AI→Base64→storage→DB publisher. Token uses
`TokenComponent` and AI uses Reactor `WebClient`; HTTP storage uses
`HttpMissionImageStorage` with another Reactor `WebClient`; R2DBC completion is
performed after storage. Base64 decoding is local work on `Schedulers.parallel()`.

## Phase 2 independent variable

Only permit holding scope changes: BEFORE holds the full request publisher;
AFTER holds only the token, AI and storage WebClient publishers. The shared
limit remains 320 and zero-wait policy remains. Base64, DB and response
composition do not hold the HTTP permit.
