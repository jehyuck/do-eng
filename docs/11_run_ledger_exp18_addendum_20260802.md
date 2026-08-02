# Experiment 1-8 Run Ledger Addendum

기준 branch: `experiment/doeng-outbound-pool-isolation`
corrected source: `fdc7e93acf166a9a79f651eab817220d26c18aa8`
조건: WebFlux VU200 / 105s / AI 2000ms / storage 100ms / pool active 400 / pending 800 / admission OFF / JFR OFF

| Run ID | 종류 | Arm | 상태 | 결과 경로 | 기록 |
|---|---|---|---|---|---|
| `RUN-20260802-EXP18-ISOLATED-SCOUT-001` | scout | ISOLATED | SETUP FAILURE | `experiment/results/RUN-20260802-EXP18-ISOLATED-SCOUT-001/` | 기존 wrapper의 compose project가 `doeng-exp13`으로 고정되어 port 9100 충돌. 부하 전 중단 |
| `RUN-20260802-EXP18-ISOLATED-SCOUT-002` | scout | ISOLATED | DIAGNOSTIC ONLY | `experiment/results/RUN-20260802-EXP18-ISOLATED-SCOUT-002/` | wiring correction 이전 binary. 최종 aggregate 제외 |
| `RUN-20260802-EXP18-ISOLATED-SCOUT-003` | scout | ISOLATED | DIAGNOSTIC ONLY | `experiment/results/RUN-20260802-EXP18-ISOLATED-SCOUT-003/` | corrected binary. provider 확인 완료. 일부 observer timeout 9건(raw 보존), aggregate 제외 |
| `RUN-20260802-EXP18-SHARED-001` | core | SHARED | INVALID | `experiment/results/RUN-20260802-EXP18-SHARED-001/` | poolMode는 SHARED였으나 inactive isolated provider meter가 함께 섞인 wiring/provenance mismatch |
| `RUN-20260802-EXP18-SHARED-001-RPL-001` | core | SHARED | VALID | `experiment/results/RUN-20260802-EXP18-SHARED-001-RPL-001/` | accepted 12,056, p95 8,703ms, pending max 1,292 |
| `RUN-20260802-EXP18-ISOLATED-001` | core | ISOLATED | VALID | `experiment/results/RUN-20260802-EXP18-ISOLATED-001/` | accepted 3,745, p95 8,538ms, pending max 1,313 |
| `RUN-20260802-EXP18-ISOLATED-002` | core | ISOLATED | VALID | `experiment/results/RUN-20260802-EXP18-ISOLATED-002/` | accepted 9,606, p95 7,541ms, pending max 1,083 |
| `RUN-20260802-EXP18-SHARED-002` | core | SHARED | INVALID | `experiment/results/RUN-20260802-EXP18-SHARED-002/` | stage observer timeout 1건 |
| `RUN-20260802-EXP18-SHARED-002-RPL-001` | replacement core | SHARED | INVALID | `experiment/results/RUN-20260802-EXP18-SHARED-002-RPL-001/` | load-stop/drain 초기 snapshot 및 reconnect artifact 누락 |
| `RUN-20260802-EXP18-SHARED-003` | core | SHARED | VALID | `experiment/results/RUN-20260802-EXP18-SHARED-003/` | accepted 12,291, p95 8,732ms, pending max 1,679 |
| `RUN-20260802-EXP18-ISOLATED-003` | core | ISOLATED | VALID | `experiment/results/RUN-20260802-EXP18-ISOLATED-003/` | accepted 8,541, p95 8,414ms, pending max 782 |

## Validity 집계

- SHARED: VALID 2 / 3 필요 조건 미달
- ISOLATED: VALID 3
- 최종 aggregate: 생성하지 않음
- 최종 분류: F — INVALID / VALID cohort 미완성

## 보존 규칙

모든 raw, invalid run, setup failure, scout는 삭제하지 않았다. 성능 outcome은 validity와 분리했으며, 추가 실행·튜닝은 hard stop으로 중단했다.
