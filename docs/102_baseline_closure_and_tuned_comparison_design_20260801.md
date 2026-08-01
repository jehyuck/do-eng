# DoEng WebFlux Validation — Baseline Closure and Tuned Comparison Design

Status: DESIGN / NO EXECUTION

## 1. Baseline closure decision

**CLOSE — with bounded claims.**

The baseline phase has enough valid evidence to close the original execution-
model question. Later remediation and tuning results remain separate artifacts
and must not rewrite the baseline conclusion.

## 2. Baseline research question

Under the fixed synthetic image/I-O workload and the recorded 2 CPU / 3 GiB
application envelope, how did the corrected WebFlux path compare with MVC200,
and what changed when MVC worker capacity was explicitly raised to MVC400?

This question is about the tested configurations, not about WebFlux or MVC in
general.

## 3. Runtime configuration interpretation

The phrase “default configuration” is not used in the claim. The baseline arms
are execution/runtime configurations:

| Arm | Runtime distinction | Shared conditions |
|---|---|---|
| WebFlux baseline | corrected REST WebFlux path with the recorded Reactor Netty event-loop/default worker configuration; no separate event-loop tuning | CPU2, memory3 GiB, pool400, DB pool10, AI2 s, storage100 ms, VU120, 1 s frame/reconnect |
| MVC200 baseline | Tomcat worker maxThreads=200 | same |
| MVC400 reference | Tomcat worker maxThreads=400 | same |

The shared outbound pool and database pool are part of the test contract, not
framework defaults. Effective values are preserved in each run's config and
environment artifacts.

## 4. Baseline included evidence

The final VU120 cohort is used for the bounded baseline comparison:

| Arm | Included runs | Median p95 | Median HTTP200 | Interpretation |
|---|---|---:|---:|---|
| WebFlux | RUN-20260731-223, 233, 243 | 2,478 ms | 11,642 | two stable runs and one degraded replacement; variability retained |
| MVC200 | RUN-20260731-225, 229, 239 | 9,551 ms | 4,249 | repeated worker-capacity degradation |
| MVC400 reference | RUN-20260731-227, 231, 235 | 2,470 ms | 11,675 | stable historical reference, not a framework-wide control |

The raw status mix, p99, aborts, drain and resource artifacts remain the source
of truth. Median values summarize these runs; they do not erase run-to-run
variation.

## 5. Baseline supported claim

Within this tested VU120 synthetic envelope, MVC200 showed materially worse
latency and fewer completed HTTP200 outcomes than the corrected WebFlux and
MVC400 reference runs. Raising Tomcat worker capacity to 400 was associated
with a materially different MVC outcome.

This supports a configuration-sensitive worker-capacity observation. It does
not prove that WebFlux is universally faster, that MVC is inherently inferior,
or that MVC400 is equivalent to WebFlux's execution model.

## 6. MVC400 reference conclusion

MVC400 is a separate reference arm for the question:

> Was the MVC200 result sensitive to Tomcat worker capacity?

The observed MVC200→MVC400 difference supports that question in this envelope.
It must not be presented as “MVC was fixed” or as a direct tuned comparison
unless a separately preregistered symmetric experiment is executed.

## 7. WebFlux failure diagnosis state

The baseline closure preserves the later causal diagnosis separately:

- Experiment 1-2: AI-only admission was insufficient (`C — CONTROL INSUFFICIENT`).
- Experiment 1-3 diagnostic: shared `doeng-external` pool reached active400 and
  pending-acquire overflow; `PoolAcquirePendingLimitException` was directly
  correlated with HTTP500 (`R5 supported`).
- Experiment 1-3 full-path admission: three VALID runs prevented uncontrolled
  HTTP500 but converted overload to controlled HTTP503 (`A — stabilized within
  the fixed envelope`).

These are remediation/diagnostic results, not baseline results.

## 8. Configuration-level remediation options

| Option | Rationale | Risk | Decision |
|---|---|---|---|
| MVC worker400 | directly tests the MVC worker-capacity hypothesis | changes comparison arm | historical reference already exists |
| pool500/greater | tests shared pool ceiling | changes protected resource and did not yield reproducible stability | closed; no further sweep |
| HTTP pending/timeout tuning | may move failure boundary | masks mechanism and changes contract | rejected |
| resource/DB tuning | may move a shared bottleneck | confounds causal question | rejected |

## 9. Code-level remediation options

| Option | Evidence fit | Portfolio value | Status |
|---|---|---|---|
| AI-only admission | bounded one stage but left pool failures | limited | rejected by Experiment 1-2 |
| full-path admission | directly prevented uncontrolled failures | strong overload-control evidence | completed in Experiment 1-3 |
| per-outbound-call shared permit | tests resource-aligned holding scope | strong mechanism follow-up | proposed Experiment 1-4 |
| Base64 scheduler change | no direct dominance evidence | speculative | rejected |
| detached-subscription rewrite | not present in current REST path | unrelated to observed REST failure | rejected |

## 10. Recommended remediation direction

The next mechanism experiment should compare only:

```text
full-path permit holding
vs
shared permit held around each actual outbound WebClient call
```

The permit budget remains 320, zero-wait fail-fast remains fixed, and DB/R2DBC
remains outside the HTTP permit. Experiment 1-4's accounting gate must pass
before execution because the 1-3 core runner did not emit accepted-only latency
or complete per-run permit accounting.

## 11. Staged follow-up plan

### 2-A — diagnosis closure

Already complete through Experiment 1-3. Entry: direct Throwable/pool/stage
correlation. Exit: R5 supported and one remediation selected.

### 2-B — WebFlux before/after

This is Experiment 1-4. Entry: corrected accounting contract and preregistered
budget/holding scope. Minimum: corrected BEFORE plus one scout plus three VALID
AFTER runs. Exit: A/B/C/D/E classification; no second remediation.

### 2-C — tuned WebFlux vs MVC400

Only consider after 2-B. Use a new, symmetric, preregistered comparison with
the same workload, resources, fixture, observability and run count. MVC400's
historical runs may provide context but must not be silently merged with tuned
WebFlux results.

## 12. Fairness matrix for future tuned comparison

| Dimension | Tuned WebFlux | MVC400 |
|---|---|---|
| business path | same request contract | same request contract |
| CPU/memory | identical | identical |
| pool/DB/mock | identical | identical |
| worker/admission change | explicitly listed as WebFlux treatment | explicitly listed as MVC treatment |
| workload | identical | identical |
| validity | same instrumentation/provenance rules | same rules |
| claim | tested configuration only | tested configuration only |

If only WebFlux receives an overload-control correction, the comparison is a
treatment-versus-reference comparison, not a universal framework benchmark.

## 13. Baseline package structure

The baseline should be frozen as a separate evidence package:

```text
baseline-closure/
├─ research-question.md
├─ frozen-config.md
├─ run-index.md
├─ result-summary.md
├─ claim-evidence-map.md
├─ limitations.md
└─ raw-links.md
```

Remediation and tuned comparison belong in separate packages and must not alter
the baseline files.

## 14. Claim matrix

### Supported

- The tested WebFlux, MVC200 and MVC400 configurations produced different
  outcomes under the fixed VU120 envelope.
- MVC200's result was sensitive to its Tomcat worker capacity in this test.
- WebFlux's later HTTP500 failure mode was associated with shared outbound pool
  pressure and was controlled by full-path admission in Experiment 1-3.

### Not supported

- WebFlux is universally superior to MVC.
- MVC400 proves MVC and WebFlux are equivalent.
- Pool500 or worker/resource tuning produces a production capacity limit.
- The synthetic mock result generalizes directly to real AI/S3 behavior.

## 15. Hard stop

No code/configuration change, build, performance run, dependency addition,
execution prompt, commit or push is authorized by this design review.

## 16. Decisions requested before follow-up execution

1. Approve closing the baseline with the bounded claim above.
2. Approve keeping MVC400 as historical/context reference, not a new baseline arm.
3. Approve Experiment 1-4 only after its accounting gate is corrected and
   preregistered.
