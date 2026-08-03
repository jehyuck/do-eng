# Experiment 1-21 native log capture readiness

The native wrapper invokes `docker.exe` through `System.Diagnostics.Process`, redirects stdout and stderr to separate files, waits for the exit code, and does not treat non-empty stderr as failure. A passed capture requires exit code 0, at least one non-empty stream, and non-empty `application.log`; the raw streams are primary evidence. This document is updated only with fixture, probe, and PLAN results. Warm-up, k6, and core are prohibited in this readiness stage.

The normal-stderr fixture and non-zero fixture pass. Both baseline and remediation Docker capture probes pass with exit code 0 and non-empty stderr (92 bytes), and the six-core PLAN reports warm-up/k6/core all zero.
