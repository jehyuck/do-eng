# Experiment 1-20 Pool Collector Measurement Coverage Gate

## 목적

기존 collector harness는 150초 동안 1초 주기로 실행되고 실패 수가 0인지 확인했지만, core 시작 전 첫 표본과 core 종료 후 마지막 표본을 보장하지 못했다. 이 문서는 그 관측 공백을 measurement-validity gate로 보강한 기록이다.

## 고정 조건

Baseline은 FIFO / idle 0ms / eviction 0ms, remediation은 LIFO / idle 3000ms / eviction 1000ms다. VU 200, core 105초, drain 30초, AI 2000ms, storage 100ms, timeout 10초, pool 400 / pending 800, DB pool 10, admission 320, app 2 CPU / 3 GiB, frozen image와 6개 crossover 순서는 바꾸지 않았다. Collector도 150초 / 1000ms를 유지한다.

## 실행 경로 gate

1. collector process를 시작하고 `collectorProcessStartedAt`을 UTC ISO-8601로 기록한다.
2. JSONL 파일과 첫 유효 JSON 표본을 최대 10초 기다린다. process 조기 종료, 파일 부재, malformed first line, first-sample failure, timestamp parse 실패는 `COLLECTOR_NOT_READY`다.
3. readiness가 확인된 뒤에만 `coreInvocationStartedAt`을 기록하고 core runner를 호출한다.
4. core runner가 정상 반환한 직후 `coreInvocationCompletedAt`을 기록한다.
5. collector 종료와 마지막 유효 표본을 기록한 뒤 coverage를 판정한다.

실패 시 core를 시작하지 못한 경우에도 target을 `EXECUTION_FAILED`로 보존한다. collector JSONL·summary·coverage 원본은 삭제하지 않는다.

## `pool/collector-coverage.json`

각 core result는 다음 필드를 가진다: runId, collectorDurationSeconds, intervalMilliseconds, collectorProcessStartedAt, collectorFirstValidSampleAt, coreInvocationStartedAt, coreInvocationCompletedAt, collectorProcessCompletedAt, collectorLastValidSampleAt, validSampleCount, invalidSampleCount, collectorFailures, coversCoreStart, coversCoreEnd, timestampsNonDecreasing, coverageStatus. 실패 원인은 보조 필드 `failureType`으로 남긴다.

통과 조건은 다음을 모두 만족하는 것이다.

- 첫 유효 표본이 core invocation 시작 시각 이하
- 마지막 유효 표본이 core invocation 완료 시각 이상
- 모든 non-empty JSONL line이 JSON으로 파싱됨
- 모든 표본 timestamp가 파싱되고 비감소 순서
- valid sample 2개 초과, invalid sample 0, collector failure 0, process exit 0

통과 상태는 `COLLECTOR_COVERAGE_PASSED`다. 실패 상태는 `COLLECTOR_COVERAGE_FAILED`이며 `COLLECTOR_NOT_READY`, `COLLECTOR_STARTED_LATE`, `COLLECTOR_ENDED_EARLY`, `COLLECTOR_INVALID_JSONL`, `COLLECTOR_REPORTED_FAILURE`, `COLLECTOR_TIMESTAMP_INVALID` 중 하나를 남긴다.

## 무부하 fixture 검증

Docker나 real workload 없이 temp directory에서 다음 네 fixture를 실행한다.

- PASS: first < core start, last > core end, valid JSONL, failure 0 → PASSED
- LATE: first > core start → `COLLECTOR_STARTED_LATE`
- EARLY: last < core end → `COLLECTOR_ENDED_EARLY`
- MALFORMED: malformed JSONL line → `COLLECTOR_INVALID_JSONL`

## collector-only preflight와 PLAN

각 condition의 preflight는 process start, first-valid readiness, 전체 JSON parse, timestamp 비감소, failure 0, 정상 종료만 확인하고 `COLLECTOR_PROBE_READY`를 남긴다. core coverage를 통과했다고 주장하지 않는다.

PLAN은 여섯 crossover manifest에 readiness, core start/end timestamp, coverage validation과 coverage artifact requirement를 기록한다. PLAN 및 preflight는 warm-up, k6, core 모두 0회여야 한다.

## 상태

이 문서는 harness 보강 문서다. performance run과 정책 효과 판정은 아직 수행하지 않는다.
