# Experiment 1-29 Collector Bounded Transient Loss 계약

## Contract

Collector lifecycle validity와 observation validity를 분리한다.

- lifecycle은 stopped-by-signal, stop signal observed, summary/process exit code 0을 요구한다.
- observation `COMPLETE`: failures 0, maxConsecutiveFailures 0.
- observation `BOUNDED_TRANSIENT_LOSS`: failures 1, maxConsecutiveFailures 1, invalid JSONL 0, core start/end coverage, maximum valid-sample gap 8,000ms 이하.
- 그 외 observation은 INVALID다.
- bounded loss의 failure row는 원본 JSONL과 summary에 그대로 보존한다.

8,000ms는 5,000ms collector request timeout과 3,000ms polling/scheduling allowance의 사전 고정 합이다. 이번 계약에서 timeout, interval, workload, resource, collector 동작은 변경하지 않는다.

## Existing artifacts

- BASELINE-001: COMPLETE, 기존 artifact validation PASS
- REMEDIATION-001: COMPLETE, 기존 artifact validation PASS
- BASELINE-002 staging: lifecycle PASS, BOUNDED_TRANSIENT_LOSS (`failures=1`, `maxConsecutiveFailures=1`, `maximumValidSampleGapMilliseconds=7565.573`)
- 기존 run과 staging artifact는 수정하지 않는다.

## Regression

O1–O7 collector observation/lifecycle, C1–C6 cleanup, P1–P6 capture, D1–D5 load-stop, L1–L4 lifecycle, PowerShell/JavaScript syntax, Exp129 PLAN을 실행 전에 검증한다.
