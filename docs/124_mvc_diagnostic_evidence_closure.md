# MVC Diagnostic Evidence Closure

## Scope and status

This document closes the 2026 MVC diagnostic sequence using existing evidence only. No additional workload, T03–T07 case, boundary matrix, WebFlux rerun, JFR rerun, code change, or configuration change was performed for this closure.

- Evidence HEAD: `0ad8a69582f157a32093e15f066ed95b0d30c5d4`
- MVC diagnostic status: `CLOSED`
- First unstable boundary: `T02`
- Additional diagnostic runs: `NOT_REQUIRED`

All statements below refer to the 2026 follow-up experiments, not the original 2023 project result.

## Canonical topology

| Case | Condition | Classification |
|---|---|---|
| T00 | Ingress + SMALL | STABLE |
| T01 | Ingress + REAL | STABLE |
| T02 | AI + REAL + AI delay 1000 ms | COLLAPSE |

Therefore `PREVIOUS_STABLE_CASE=T01` and `FIRST_UNSTABLE_BOUNDARY=T02`.

## AI-delay isolation

The canonical T02 AI1000 run recorded 0.3844% success, 99.6156% timeout, p50 10049 ms, p95 10154 ms, p99 10207 ms, Tomcat busy max 400, Tomcat queue max 6544, and HTTP active max 400.

With the artificial AI delay removed, while retaining the REAL payload and the same MVC/runtime contract, T02 AI0 recorded 0.6935% success and 99.3065% timeout. Tomcat busy max remained 400, Tomcat queue max was 6796, and HTTP active max was 400.

`AI_DELAY_1000MS_AS_SOLE_CAUSE=REJECTED`: removing the artificial delay did not restore stability.

## Mock-capacity isolation

The baseline mock used 0.5 CPU and 256 MiB. The AI0 mock-capacity run used a run-only override of 4.0 CPU and 1 GiB; MVC resources and workload conditions were held constant.

The expanded-mock run recorded 61.6486% success, 42.6139% timeout, p50 8580 ms, p95 10020 ms, p99 10033 ms, max in-flight 1600, Tomcat busy max 400, Tomcat queue max 1917, and HTTP active max 400. It remained `COLLAPSE` under the registered rule.

Thus:

- `MOCK_CAPACITY_CONFOUNDER_CONFIRMED=NO`
- `MOCK_CAPACITY_EFFECT=MATERIAL`

Mock capacity materially amplified the observed instability but did not solely explain it.

## Payload interaction isolation

Under the same AI0, expanded-mock, MVC resource, workload, fixture, and endpoint conditions:

| Metric | REAL payload | SMALL payload |
|---|---:|---:|
| Binary bytes | 265745 | 1024 |
| Request JSON bytes | 354363 | 1403 |
| Success | 61.6486% | 100% |
| Timeout | 42.6139% | 0% |
| p50 | 8580 ms | 13 ms |
| p95 | 10020 ms | 187 ms |
| p99 | 10033 ms | 774 ms |
| Max in-flight | 1600 | 161 |
| Tomcat busy max | 400 | 135 |
| Tomcat queue max | 1917 | 78 |
| HTTP active max | 400 | 47 |

The REAL-payload run was `COLLAPSE`; the SMALL-payload run was `STABLE`, with valid startup/runtime gates, Node exit code 0, complete accounting, no restart/OOM, and valid observers.

Therefore:

- `LARGE_PAYLOAD_INTERACTION_CONFIRMED=YES`
- `AI_CALL_ONLY_COLLAPSE_CONFIRMED=NO`

Under this controlled MVC diagnostic condition, the collapse is strongly associated with the interaction between the large JSON/Base64 payload and the AI outbound processing path rather than with ingress size, artificial AI delay, or mock capacity alone.

## Root-cause boundary

The evidence does not isolate a single low-level component. Keep:

```text
ROOT_CAUSE=NOT_RESOLVED_TO_SINGLE_COMPONENT
ROOT_CAUSE_PRECISION=LARGE_PAYLOAD_X_AI_OUTBOUND_PATH_INTERACTION
LOW_LEVEL_SINGLE_COMPONENT_ROOT_CAUSE=NOT_ESTABLISHED
```

Tomcat saturation, increased queueing, HTTP active connections reaching 400, and latency near the 10-second timeout are supporting observations, not proof of a single causal component.

Earlier JFR observations—Base64 decode, Jackson serialization, controller/decoder activity, Apache HTTP execution, allocation, and GC pressure—remain candidate contributors or amplifiers only. They do not prove Jackson, Base64, RestTemplate, Tomcat, blocking I/O, the HTTP pool, CPU, or the mock as the sole root cause.

## WebFlux and claim boundary

WebFlux was not rerun. Existing frozen WebFlux evidence remains separate. This closure does not claim general WebFlux superiority, faster per-request behavior, or that MVC cannot handle image workloads.

The permitted factual range for later writing is limited to this 2026 follow-up: MVC remained stable through large-payload ingress; instability first appeared when the large payload was propagated through the AI outbound path; removing artificial AI delay was insufficient; increasing mock capacity improved but did not eliminate the instability; and reducing payload size restored stable behavior.

## Evidence references

- `docs/118_mvc_t00_canonical_closure.md`
- `docs/119_mvc_t01_real_payload_result.md`
- `docs/120_mvc_t02_ai_stage_result.md`
- `docs/121_mvc_t02_ai0_confirmation.md`
- `docs/122_mvc_t02_mock_capacity_isolation.md`
- `docs/123_mvc_t02_ai0_small_payload_isolation.md`

No prior document was modified.
