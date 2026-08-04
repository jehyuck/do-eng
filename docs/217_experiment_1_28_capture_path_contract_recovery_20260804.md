# Exp128 Artifact Contract Recovery — Capture Path

## Root cause

`RUN-20260804-EXP128-BASELINE-001`에서 실제 capture 파일은 모두 생성·복사되었다. 실패는 `application/docker-logs-capture.json`의 경로 문자열 인코딩 계약에서 발생했다.

- producer 실제 파일: `application/docker-logs.stdout.log`, `application/docker-logs.stderr.log`, `application/application.log`
- producer metadata 경로: run root의 실제 absolute path
- validator 기대 경로: metadata의 경로를 `Test-Path`로 확인한 뒤 `application` 디렉터리 내부인지 검증
- 불일치: metadata를 UTF-8 무BOM으로 기록했지만 Windows PowerShell validator가 기본 인코딩으로 읽어 한글이 포함된 clone 경로가 깨짐
- 결과: 실제 파일은 존재했지만 metadata 경로에 대한 `Test-Path`가 실패하여 `Capture path missing`

따라서 producer/copy destination은 맞고, metadata serialization과 validator read encoding 사이의 contract가 불일치했다.

## 조사된 부수 상태

- `completedSteps`의 `collector lifecycle` 두 항목은 collector summary 검증 단계와 lifecycle artifact 기록 단계를 각각 기록한 기존 runner 흐름의 결과다. 이번 직접 원인은 아니다.
- container stop과 post-stop capture는 성공했지만 실패 경로의 `cleanupResult`는 runner가 실패 summary에 고정 기록하는 값이다. cleanup 성공 여부를 의미하는 정상 완료 값으로 해석하지 않는다.
- `failureDomain`과 `failureType`이 동일한 것은 catch block이 예외 메시지를 두 필드에 기록하는 기존 contract다.
- 이전 보고서의 일부 clone 경로 표기는 문서 오기이며, 실제 실행 clone은 `do-eng-exp128-clean-20260804`다.

## 최소 수정

Exp128 전용 native log capture helper를 추가하고 metadata JSON을 UTF-8 BOM으로 기록하도록 변경했다. 기존 application source, mock, workload, collector, timeout, resource, policy는 변경하지 않았다.

## 검증 경계

기존 실패 artifact는 보존한다. 수정 후 새 run ID로 BASELINE 단일 검증만 실행하며, artifact validation이 다시 실패하면 즉시 중단한다.
