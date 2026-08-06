# Exp148 Evidence Package

## 1. Experiment identity

- Experiment: Exp148 Factor A Atomicity Closure and Observation Overhead Calibration
- Branch: `experiment/exp148-factor-a-atomicity`
- Previous HEAD: `dd07a28ece81574b4830fa1398eedc5e8b8bbc90`
- Additional load: none after the two A1B0 core runs

## 2. Atomicity evidence

The preserved integration test uses a real Spring R2DBC transaction against MariaDB. The failure path rolls back the claim, progress update, and picture insert; the success and duplicate-call paths are also recorded.

## 3. Performance and diagnostic cores

The HIGH cores, client accounting, drain, consistency checks, and raw artifacts completed and were preserved. Original execution-status artifacts are copied without modification.

## 4. Original post-processing failures

- Performance: completion-marker PowerShell expression failure after core and cleanup.
- Diagnostic: summarizer strict-property failure on a sparse stage snapshot after core and cleanup.

The original execution-status files remain `EXP148_EXECUTION_STOPPED`. Recovered summaries were generated from preserved raw artifacts without starting additional load.

## 5. Calibration result

The recovered calibration classification is `OBSERVATION_OVERHEAD_SEVERE`. This is an operational classification for one ordered pair, not a statistical significance claim.

## 6. Known test-suite failure

The full Gradle suite recorded one existing `CloseAcquireRaceAttributionTest` assertion failure. It is preserved separately and was not reclassified as an Exp148 atomicity failure.

## 7. Evidence limitations

The package contains minimal raw-derived evidence, not the complete results directory. Large application and client logs are intentionally excluded; their paths and derivation context remain in the source artifacts and manifest.

## 8. File manifest

See `manifest.json` for relative path, source path, SHA-256, size, provenance, and description.
