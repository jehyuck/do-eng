# Experiment 1-13 Run Ledger Addendum

| Run ID | 조건 | 상태 | 핵심 결과 | 비고 |
|---|---|---|---|---|
| SETUP-20260802-EXP113-CONTROL-001 | deterministic positive control | 실패 | correlation assertion 실패 | 재사용 fixture의 `EXP112-CONTROL`과 합성 입력의 `EXP113-CONTROL` 불일치. application/workload 문제가 아닌 runner correlation key 오류. 산출물은 `.experiment-work/experiment-1-13-controls/`에 보존 |
| SETUP-20260802-EXP113-CONTROL-RECOVERY-001 | corrected deterministic positive control | 완료 | A~H assertion 모두 통과 | workload/application 설정 변경 없이 합성 correlation key만 기존 fixture 계약에 정렬. `.experiment-work/experiment-1-13-controls-recovery-001/` |
| RUN-20260802-EXP113-BASELINE-001 | maxIdleTime 0 | VALID | AI PrematureClose 64, mock-close-before-acquire 64, HTTP 200 4,736, p95 9,180ms | 측정 완료 후 종료된 collector PID에 대한 `Wait-Process` 후처리 오류. 부하 재실행 없이 보존된 raw를 검증하고 파생 artifact만 복구 |
| RUN-20260802-EXP113-REMEDIATION-001 | maxIdleTime 4,000ms | VALID | AI PrematureClose 56, mock-close-before-acquire 56, HTTP 200 5,495, p95 8,735ms | collector failure 0, drain/정합성 완료 |
| RUN-20260802-EXP113-BASELINE-002 | maxIdleTime 0 | VALID | AI PrematureClose 4, mock-close-before-acquire 2, HTTP 200 1,729, p95 9,931ms | collector failure 0, drain/정합성 완료 |
| RUN-20260802-EXP113-REMEDIATION-002 | maxIdleTime 4,000ms | VALID | AI PrematureClose 67, mock-close-before-acquire 67, HTTP 200 6,919, p95 8,498ms | collector failure 0, drain/정합성 완료 |
| RUN-20260802-EXP113-BASELINE-003 | maxIdleTime 0 | VALID | AI PrematureClose 10, mock-close-before-acquire 9, HTTP 200 2,153, p95 9,332ms | collector failure 0, drain/정합성 완료 |
| RUN-20260802-EXP113-REMEDIATION-003 | maxIdleTime 4,000ms | VALID | AI PrematureClose 45, mock-close-before-acquire 43, HTTP 200 6,450, p95 8,632ms | collector failure 0, drain/정합성 완료 |

최종 분류: `NOT_EFFECTIVE`. 6개 core 이후 hard stop에 따라 추가 값, 추가 VU, 추가 core를 실행하지 않았다.
