# Experiment 1-19 Core Artifact Finalization Gate

## 발견한 문제

기존 core runner는 legacy 결과의 일부 최상위 파일만 Exp119 run root로 복사한 뒤 `COMPLETED` marker를 만들 수 있었다. 따라서 core 실행 완료와 Evidence artifact 완결을 같은 상태로 취급할 위험이 있었다.

## Artifact source → destination mapping

| Legacy source | Exp119 destination |
|---|---|
| `run-config.json` | `run-config.json` |
| `client-results.json` | `client-results.json` |
| `client-progress.jsonl` | `client-progress.jsonl` |
| `pool-metrics.jsonl` | `pool/pool-metrics.jsonl` |
| `application.log` | `application/application.log` |
| `database-metrics.jsonl` | `database/database-metrics.jsonl` |
| `container-stats.jsonl` | `container/container-stats.jsonl` |
| `load-stop-mock-metrics.json` | `mock/load-stop-mock-metrics.json` |
| `mock-drain-summary.json` | `drain/mock-drain-summary.json` |
| `verification-summary.json` | `verification-summary.json` |
| Exp119 runtime data | `provenance/runtime-provenance.json` |

Legacy provenance가 있으면 `provenance/legacy/`에 별도로 보존한다. placeholder나 빈 JSON은 만들지 않는다.

## Completeness rules

`Assert-Exp119RequiredArtifactCompleteness`는 모든 required path의 존재·non-empty를 확인하고, required JSON parse, pool JSONL의 최소 한 valid line, application log, database/container/provenance collector output을 확인한다.

## Terminal state rules

terminal marker는 `RUNNING`, `COMPLETED`, `EXECUTION_FAILED` 중 하나만 존재한다.

- 모든 artifact gate 통과 뒤에만 `COMPLETED`를 만든다.
- 실행·복사·검증·cleanup 중 실패하면 `failure-summary.json`을 기록하고 `EXECUTION_FAILED`만 남긴다.
- HTTP 오류나 latency 자체는 runner failure가 아니다. process, artifact, verification, cleanup 실패만 runner failure다.

## Aggregator alignment

`aggregate-experiment-1-19.js --readiness`는 `COMPLETED` marker, `EXECUTION_FAILED` 부재, 모든 required artifact, `execution-summary.executionStatus=COMPLETED`, `artifactValidation=PASSED`, 유효 pool JSONL line을 모두 만족한 run만 completed로 센다.

## Fixture verification

`test-experiment-1-19-artifact-finalization.ps1`는 시스템 임시 경로에서만 fake legacy artifact를 만든다.

- complete fixture: copy, gate, `COMPLETED`, aggregator recognition 통과
- missing-pool fixture: gate 실패, `EXECUTION_FAILED`, aggregator exclusion 통과

이는 performance result가 아니며 Docker, warm-up, k6, reset, drain을 실행하지 않는다.

## PLAN side-effect zero

PLAN은 6개 command manifest와 readiness만 생성한다. warm-up, k6, core, Docker Compose up, core result directory 생성은 0이어야 한다.

## 최종 판정

fixture와 PLAN side-effect 검증이 통과하면 `CORE_RUNNER_READY`다. 이는 실행 경로 준비 상태일 뿐 정책 효과나 measurement validity를 뜻하지 않는다.
