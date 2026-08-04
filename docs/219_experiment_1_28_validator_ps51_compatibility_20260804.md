# Exp128 Artifact Validator PowerShell 5.1 호환성 복구

## Root cause

보존된 `RUN-20260804-EXP128-BASELINE-001-DRAIN-CONTRACT`는 load-stop과 drain을 포함한 모든 관측 자료가 정상이어도, Windows PowerShell 5.1에 없는 `System.IO.Path.GetRelativePath` 호출 때문에 artifact validation 단계에서 실패했다.

## Change

`experiment/scripts/experiment-1-25-artifact-contract.ps1`의 capture containment 검사를 `GetFullPath`와 directory-separator 경계가 있는 `StartsWith(..., OrdinalIgnoreCase)` 검사로 교체했다. 이 방식은 sibling prefix collision과 parent-directory escape를 허용하지 않는다. `Test-Path -LiteralPath`도 사용한다.

Production application, mock, image, workload, timeout, VU, duration, pool, admission, collector, lifecycle policy, load-stop contract, capture metadata format은 변경하지 않았다.

## Compatibility regression

`test-experiment-1-28-validator-ps51.ps1`에서 P1–P6을 검증했다.

- P1 정상 Korean/Unicode 경로: PASS
- P2 sibling prefix: REJECT
- P3 parent escape: REJECT
- P4 missing capture file: `Capture path missing`
- P5 filename mismatch: `Capture filename identity failed`
- P6 valid capture: PASS
- PowerShell executable: `powershell.exe`
- `GetRelativePath` production validation occurrence: 0

## Preserved artifact read-only validation

원본 diagnostic artifact는 복사·수정하지 않았다. capture identity, stop identity, collector lifecycle, collector coverage, artifact path preflight, runtime provenance, base artifacts 검증을 보존 경로에서 통과했다.

## Existing validation

D1–D5 load-stop contract, JavaScript syntax, 기존 L1–L4 회귀 결과, Exp128 Six-Core PLAN과 표준 manifest 6개를 유지한다. 이번 작업에서는 diagnostic run, 기존 run 재실행, Six-Core, aggregate, 성능 분석, 정책 판정을 수행하지 않는다.
