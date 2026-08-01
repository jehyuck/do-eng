# DoEng Experiment 1-4 Phase 1-R Final Result

## Phase status

- Experiment 1-3 safety evidence: PRESERVED
- Experiment 1-4 Phase 1 accounting correction: PRESERVED
- Experiment 1-4 Phase 1-R observer recovery: **CLOSED**
- Corrected BEFORE: **3 VALID runs**
- AFTER threshold: **FROZEN**
- Experiment 1-4 Phase 2: NOT STARTED
- Tuned comparison/MVC: NOT STARTED

## What was proved

- The prior observer failure had a direct synchronous `spawnSync` boundary.
- The recovered observer runs asynchronously, prevents overlapping DB samples,
  preserves command timing/error evidence and survives VU200 load.
- Corrected WebFlux BEFORE produced three valid, reproducible measurements
  under the frozen contract.
- The preregistered BEFORE aggregate and AFTER thresholds are now fixed.

Observer coverage for the three valid runs was 138/145 (95.2%), 143/145
(98.6%) and 142/145 (97.9%) for the phase-1 endpoint cycle; all had zero
final observer failures. DB/container monitor failures were also zero.

## What was not proved

- No per-outbound-call admission implementation was evaluated.
- No WebFlux-vs-MVC superiority or production-capacity claim was made.
- No Phase 2/AFTER result exists.

## Final state

`OBSERVER RECOVERED`
`CORRECTED BEFORE 3 VALID`
`AFTER THRESHOLD FROZEN`
`PHASE 2 NOT STARTED`
