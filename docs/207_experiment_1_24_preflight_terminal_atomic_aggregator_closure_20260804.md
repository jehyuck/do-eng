# Experiment 1-24 Aggregator / Preflight Terminal / Atomic Metadata Closure

## Exp123 closure

Exp123는 INVALID 상태로 보존한다. raw outcome은 검사하지 않았고, 동일 ID 재실행 및 잔여 run 실행은 하지 않았다.

## Aggregator

aggregate-experiment-1-24.js는 preflight, runConfig, executionSummary, collectorSummary, lifecycle, coverage, runtimeProvenance, timeline, containerStop, logCapture를 명시적 변수로 읽는다. 각 artifact의 역할을 다른 artifact 변수로 대체하지 않는다.

run identity, policy, Compose SHA-256, collector lifecycle/coverage, preflight evidence, stop/capture, terminal marker를 검증한다.

## Preflight terminal

RUNNING marker를 preflight 전에 생성하고 preflight를 runner try 경로 안에서 실행한다. 실패 시 RUNNING을 제거하고 EXECUTION_FAILED, failure-summary.json, execution-summary.json을 남긴다. failureDomain은 ARTIFACT_PATH_PREFLIGHT로 분류하며 실제 failureType을 보존한다.

## Preflight evidence

7개 required directory 각각에 directory existence, canonical containment, write probe 생성/내용 확인, delete probe, 삭제 후 부재를 기록한다. preflight artifact는 runId와 run-config identity를 검증한다.

## Atomic metadata

container-stop은 metadata parent를 먼저 생성하고 temporary metadata를 final로 rename한다. capture helper는 application directory를 보장하고 docker-logs-capture.json.tmp를 작성·parse한 뒤 final metadata로 atomic publish한다. JSON writer는 BOM 없는 UTF-8을 사용한다.

## Fixtures

- X1~X9: artifact path preflight fixture 통과
- X10: synthetic six-run aggregator acceptance 통과
- X11~X18: identity, summary, preflight, containment, probe, capture, container-stop, terminal mutation rejection 통과
- BASELINE/REMEDIATION production-path preflight probe 통과
- six-core PLAN 통과

실제 warm-up, k6, core, performance analysis, policy decision은 수행하지 않았다.

## 판정

Exp124는 six-core 실행 준비 상태로 유지한다. 실제 실행은 별도 승인 전까지 금지한다.

