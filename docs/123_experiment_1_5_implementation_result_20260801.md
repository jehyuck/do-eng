# Experiment 1-5 Implementation Result

## Behavioral equivalence gate

PASS. Current `FULL_PATH` keeps one outer `AiOutboundAdmissionGate` around
the token -> AI -> decode -> storage -> DB publisher. In `FULL_PATH`,
`executeStage` returns the action directly, so TOKEN/AI/STORAGE per-call gates
are inactive. Release remains in `doFinally` on complete/error/cancel. The
only runtime experiment change was `maxConcurrent=352`.

## Changed files

- `backend/docker-compose.experiment-1-5-fullpath352.yaml`: experiment image,
  `FULL_PATH`, permit 352.
- `experiment/scripts/run-experiment-1-5-fullpath352.ps1`: narrow wrapper over
  the recovered Phase 1-R runner.
- `docs/122_experiment_1_5_preregistered_design_20260801.md` and result docs.

No business chain, observer, pool, workload, or resource implementation was
changed. Docker JDK11 tests passed and the experiment image built successfully.

## Preflight

Management health was `UP`; admission endpoint reported `FULL_PATH`, limit 352,
current 0, and permit leak 0 before load. Pool 400, DB pool 10, 2 CPU/3 GiB,
VU200, 1-second pacing, 2,000 ms AI, 100 ms storage, 10-second timeout and
fresh-JVM recreation were confirmed.
