# Experiment 1-21 terminal-commit Evidence gate

Exp121 finalization was aligned before any core execution. Required artifacts are split into non-empty files and raw stream files that may be zero bytes; the contract requires the two raw streams to exist and their combined byte count to be positive. Native capture uses direct stdout/stderr redirection to files and validates exit code, metadata byte counts, paths, and combined log size.

The execution timeline is created before core invocation and records core start immediately before invocation, core completion immediately after return, capture boundaries, collector completion, artifact-validation completion, and finalization completion. The runner writes `FINALIZING/PENDING`, validates the structure, then writes `COMPLETED/PASSED` and only then commits the `COMPLETED` marker. Failure coverage is preserved if it already exists, and failure summaries include a failure domain.

The aggregator validates the same artifact contract, capture metadata and file sizes, run-local paths, complete timeline ordering, passed collector coverage, completed summary, and terminal marker. Residual Exp120 references in Exp121 execution code are absent.

Fixtures A–G, both no-load capture probes, and the six-run PLAN passed. Warm-up, k6, core, performance analysis, and policy decision remain unexecuted.
