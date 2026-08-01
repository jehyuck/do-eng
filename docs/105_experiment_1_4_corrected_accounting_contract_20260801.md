# Experiment 1-4 Phase 1 — Corrected Accounting Contract

## Load lifecycle

1. PRE-RUN requires fresh JVM, matching fixture/configuration, login completion,
   mock AI/storage idle and collector readiness.
2. MEASUREMENT lasts 105 seconds. VUs continue one-second frame scheduling.
3. LOAD STOP prevents new scheduling and immediately records request and mock
   in-flight state.
4. DRAIN observes the existing 30-second mock drain contract.

## Outcome categories

Every completed request is assigned exactly one category:

`HTTP_200_ACCEPTED`, `HTTP_503_CONTROLLED_REJECTION`,
`HTTP_500_UNCONTROLLED`, `HTTP_OTHER`, `CLIENT_TIMEOUT`, `CLIENT_ABORT`,
`CONNECTION_ERROR`, or `UNCLASSIFIED`.

Accepted-only, controlled-rejection, uncontrolled and all-completed latency
populations are reported independently.

## Accounting invariants

```text
completed classified = sum(all outcome categories)
started = completed at load stop + unfinished at load stop
started = final completed + final unfinished
success-triggered VU exits = 0
premature VU exits = 0
```

Admission/stage counters separately verify:

```text
acquired = released + final in-use
final in-use = 0
permit leak = 0
max in-use <= 320
```

These are measurement-validity checks. High latency, 503, 500, timeout,
backlog and drain time remain system outcomes, not automatic invalidation.

## Compatibility boundary

`ACCOUNTING_MODE=legacy` preserves the historical driver semantics. The new
Phase 1 runs use `ACCOUNTING_MODE=corrected`; this prevents silent rewriting of
earlier run provenance.
