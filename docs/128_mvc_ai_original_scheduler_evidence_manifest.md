# MVC Original Scheduler Evidence Manifest

## Closure metadata

- Closure base HEAD: `af64cc467e2277a95e8ae541725a835ca025cf7c`
- Canonical raw candidate: `MVC-AI-ORIGINAL-SCHED-001`
- Raw artifact root: `experiment/results/MVC-AI-ORIGINAL-SCHED-001`
- Measurement validity: `true`
- Node exit code: `0`
- Valid raw measurement count: `1`
- Registered one-run contract: `VIOLATED`
- Second execution trigger: `NOT_ESTABLISHED`
- Performance workload executed during this closure: `NO`

## Raw candidate fingerprint

- Started at: `2026-08-11T16:09:43.779Z`
- Finished at: `2026-08-11T16:10:58.845Z`
- Load stopped at: `2026-08-11T16:10:43.796Z`
- Started: `7,276`
- Completed: `7,276`
- Unfinished: `0`
- Successful: `1,085`
- Client timeout: `6,059`
- Connection error: `0`
- HTTP 500: `132`
- Success rate: `14.91%`
- Max in-flight: `1,598`
- Classification: `COLLAPSE`
- Fixture bytes: `265,745`
- Fixture SHA-256: `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- Node: `v24.14.0`
- Load scenario: `reconnect-ramp`
- Arrival mode: `staggered`
- Active missions: `160`
- Activation interval: `3,000 ms`
- Reconnect delay: `1,000 ms`
- Frame interval: `1,000 ms`
- Duration: `60,000 ms`
- Request timeout: `10,000 ms`
- Target: `/experiment/mvc-probe?mode=AI&runId=MVC-AI-ORIGINAL-SCHED-001&answer=happy`
- Success JSON path: `ai.result`
- MVC image ID: `sha256:984fa39f3ab397d831086f8bef96402180c1d80d2d47b0a0274b2189652b6d4d`
- Mock image ID: `sha256:0bbf354a08732a5dbfd3a3013218a6f1955d74c1bc41ecc407e819ba1788bbf6`

All recorded validity gates passed: image, fresh project, Node runtime, startup,
MVC runtime, mock runtime, client accounting, scheduler, observer, and final
container state. The raw candidate is preserved under the ignored result root and
is force-tracked below without modifying its contents.

## Tracked raw files

| Path | Bytes | SHA-256 |
|---|---:|---|
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/measurement-validity.json` | 570 | `31416e11f5be2ab7a167f01e4c9d77639a9bb4505e293f1316f5821f9a4cd53f` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/client-results.json` | 8,010,500 | `e22ea7d896288cad873cdd40f8811e2c9c2aaca71ef670af4c0ef4f5f348e83d` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/client-process-contract.json` | 1,180 | `49d6fc85ab375e2c1bc2c95366ccae60de307bb4fde99b8da37b61275f6fb7c1` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/node-runtime-contract.json` | 303 | `da0787629effc7ab826dd4240cfe85d36fd2f51369e3c8c71daf05d238e94b6c` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/scheduler-contract.json` | 316 | `d3954ececd54b3a5a4a6872b85f59f33f11bc9646bb97490c437671bf568fbaa` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/client-accounting-contract.json` | 179 | `87fc40d1a4fd513518236f9b02447bc16f572ededd4cc82caf3c30db2bd45fad` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/observer.summary.json` | 607 | `9c941699db2ff8c68e1a6770b040c72dce4e17a3e983f5dcc040396818fd0f8d` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/observer.jsonl` | 21,412 | `e17c40a910ced706b51d8710602bec5d783ad5f638491b1a3e341a821921860b` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/mvc-final-state-contract.json` | 539 | `0c04a0df48cb9cd5067c8c4dfa8b032caf8b6a84f2408479a7417d3ccab31396` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/mock-final-state-contract.json` | 539 | `40dccbf24d36442aad88ed7b9fded8e3db443aefab6718cbc6087a19b93cad9b` |
| `experiment/results/MVC-AI-ORIGINAL-SCHED-001/initial-arrival-summary.json` | 814 | `131e39fa854689551c5365613433f44c278cf6b2a52ff62b98ae695c88f89687` |

## Candidate A disposition

Candidate A (`started=8,909`, `successful=967`, `timeout=6,441`,
`connectionError=1,490`, `HTTP 500=11`) is recorded in docs/127 but its raw
result directory and raw files were not found under `experiment/results/` or
`experiment/results/bootstrap-history/` during this closure.

`CANDIDATE_A_RAW_FOUND: NO`

`CANDIDATE_A_STATUS: DOCUMENTED_BUT_RAW_PROVENANCE_UNAVAILABLE`

`CANDIDATE_B_RAW_FOUND: YES`

`CONTRACT_EQUIVALENCE: NOT_VERIFIABLE`

Both candidates are documented as `COLLAPSE`. The evidence does not establish
which execution occurred first, nor does it establish a trigger for the second
execution. Scheduler interpretation remains:

`SCHEDULER_SEMANTICS_EFFECT: NOT_SUFFICIENT`

`IMMEDIATE_FIXED_SCHEDULER_CONFOUNDER: NOT_ESTABLISHED`
