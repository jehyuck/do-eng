# Exp141 Pool Run Inventory

## 기준

- 기준 commit: `86d5de666ca497f267efc36a822df61bdf3e94bf`
- 작업 유형: read-only evidence reconstruction
- 신규 부하 실행: 없음

## Run inventory

| Run ID | Pool / pending | Workload | Duration | App resource | Mock delay | Status | Evidence location |
|---|---:|---|---:|---|---|---|---|
| `SMOKE-20260728-012` | 200 / 확인 불가 | 단일 correctness 요청 | 확인 불가 | 확인 불가 | AI=false | `VALID_HISTORICAL` | `docs/11_run_ledger.md:178` |
| `RUN-20260801-EXP13-CORE-001` | 400 / 확인 불가 | VU200, AI 2s, storage 100ms | 105s | 2 CPU / 3GiB | mock | `VALID_HISTORICAL` | `docs/99_experiment_1_3_final_result_20260801.md` |
| `RUN-20260801-EXP13-CORE-002` | 400 / 확인 불가 | VU200, AI 2s, storage 100ms | 105s | 2 CPU / 3GiB | mock | `VALID_HISTORICAL` | `docs/99_experiment_1_3_final_result_20260801.md` |
| `RUN-20260801-EXP13-CORE-003` | 400 / 확인 불가 | VU200, AI 2s, storage 100ms | 105s | 2 CPU / 3GiB | mock | `VALID_HISTORICAL` | `docs/99_experiment_1_3_final_result_20260801.md` |
| `RUN-20260801-EXP13-DIAG-002` | 400 / 800 계약, sampled pending 약 1,700 | VU200, diagnostic | 105s | 2 CPU / 3GiB | mock | `DIAGNOSTIC_INCONCLUSIVE` | `docs/98_experiment_1_3_diagnostic_result_20260801.md` |
| `RUN-EXP139-POOL400-HIGH-001` | 400 / 800 | 200 active missions, 1s interval | 30s | 2 CPU / 3GiB | AI 2s / storage 100ms | `VALID_CURRENT` | `D:/T7/workspace/_작업공간/50_로컬레포/worktrees/exp139-pool-evidence-execute-6/.../final-pool-evidence.json` |
| `RUN-EXP140-POOL1000-HIGH-001` | 1000 / 800 | 200 active missions, 1s interval | 30s | 2 CPU / 3GiB | AI 2s / storage 100ms | `VALID_CURRENT` | `D:/T7/workspace/_작업공간/50_로컬레포/worktrees/exp140-pool1000-execute/.../final-pool-evidence.json` |

## Pool values not represented by a valid current raw run

- Pool 500: 문서에서 과거 후보·폐쇄 방향은 확인되지만 이 branch에서 해당 실행의 raw artifact/run ID는 확인되지 않음 (`RAW_NOT_AVAILABLE`).
- Pool 600, 700, 750, 800: 현재 자료에서 유효한 실행 raw는 확인되지 않음 (`RAW_NOT_AVAILABLE`).
- Pool 200 correctness run은 고부하 pool curve와 workload가 달라 `HISTORICAL_CONTEXT_ONLY`이다.

## Cohort classification

- `CURRENT_CONTROLLED_COHORT`: Exp139 Pool400와 Exp140 Pool1000. 두 run은 동일한 current high workload 계약에서 pool 상한만 달리한 단일 관측이다.
- `HISTORICAL_COMPARABLE_COHORT`: 없음. Exp13 core는 admission 경계와 collector/실행 계약이 달라 보조 근거로만 사용한다.
- `HISTORICAL_CONTEXT_ONLY`: Pool200 correctness, Exp13 diagnostic/core, 문서상 Pool500 후보.
- `INVALID_OR_INCONCLUSIVE`: Exp13 diagnostic 및 raw가 보존되지 않은 후보값.

## 주의

현재 branch에는 Exp139·Exp140 raw가 commit되어 있지 않다. 위 current raw 경로는 별도 clean execution worktree의 보존 artifact를 가리킨다. 이 문서는 raw를 복사하거나 수정하지 않았다.
