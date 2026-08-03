# Experiment 1-19 Fresh-First A/B preflight 결과

작성일: 2026-08-03
상태: 완료 — `READY_FOR_SIX_CORE_RUNS`
범위: harness·provenance dry-run만 수행. warm-up, k6, VU 200 105초 core는 수행하지 않았다.

## 수행한 범위

- 기준 source commit `270349fa7937eb4486087d34184461ae6aaab10a`의 `backend/doEngGameFlux` Git object만 tar build context로 사용해 application image를 한 번 생성했다.
- baseline과 remediation 각각에 대해 fresh recreate, management/app/mock health, mock idle/reset, scoped DB reset, 200개 per-VU mock token fixture, pool endpoint snapshot, collector 실행 가능성을 확인했다.
- 두 rendered Compose를 비교해 lifecycle policy 세 환경 변수 외 차이가 없음을 검증했다.
- Java 11 Docker 환경에서 `ExternalServicePropertiesTest`, `ExternalIdleFreshnessTest`, `FreshFirstLifecyclePolicyTest`를 실행했고 성공했다.

## 정책 및 동일 조건

| 항목 | BASELINE | REMEDIATION |
| --- | --- | --- |
| leasing strategy | FIFO | LIFO |
| max idle time | 0ms | 3,000ms |
| background eviction | 비활성(0ms) | 1,000ms |

그 외에는 VU 200, duration 105초, frame/reconnect 1초, AI 2,000ms, storage 100ms, request timeout 10초, drain 30초, app 2 CPU/3GiB, shared outbound pool 400/pending 800, DB pool 10, full-path admission 320, fixture/auth/reset 및 collector 계약을 고정했다. 이 문서 단계에서는 이 조건으로 실제 부하를 보내지 않았다.

## preflight gate

두 arm 모두 다음을 통과했다.

- fresh application JVM, management `/actuator/health` = UP, REST port reachability, mock health = UP
- 시작 전 mock AI/storage in-flight = 0, mock reset 후에도 0
- `mission_completion`의 `EXP119-%` 범위 DB reset 및 zero-count 확인
- `image/arc.jpg`: 265,745 bytes, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- VU 200에 대응하는 strict-auth mock user 200명과 서로 다른 token 200개 준비. raw token은 artifact에 보존하지 않고 삭제했다.
- pool endpoint 단발 snapshot, DB `docker compose exec`, container monitor 명령 및 Node runtime 사용 가능 여부 확인

## runtime configuration proof

application의 기존 pool endpoint는 pool mode와 gauge만 노출하며 lifecycle property 세 개를 직접 노출하지 않는다. 따라서 lifecycle 값의 runtime proof는 다음 둘을 분리해 남겼다.

1. 실행 중 container의 environment inspect: baseline `FIFO/0/0`, remediation `LIFO/3000/1000`을 직접 확인했다.
2. Java 11 binding/validation test: `ExternalServicePropertiesTest` 및 Fresh-First policy test로 Spring property binding과 provider 구성 계약을 확인했다.

두 arm은 모두 shared pool mode `SHARED`, max connections `400`, pending max count `800`, admission `320`으로 확인됐다.

## provenance

- source commit: `270349fa7937eb4486087d34184461ae6aaab10a`
- 작업 트리는 image build 당시 dirty였으나, image context는 Git object이므로 작업 트리 변경은 application image에 포함되지 않았다.
- frozen Dockerfile Git object SHA-256: `2cd21f5140d807fa5f302bdd7acd21376f347cdffdc8ce29a9a713aecb52537f`
- application image ID: `sha256:c2878d2847f80f3396a5cee5f02f1ec1ca3f7c14ceb8f49ea610d6e5fb6d9168`
- mock image ID: `sha256:2492f942c3931aa607293cf3da940e0e5aac0cfae91cbfe0ea88a893f0829ac1`
- 두 arm의 application image ID, mock image ID, runner SHA-256은 동일하다.

## controlled diff 판정

`controlled-compose-diff.txt`와 `runtime-config-diff.json`에서 다음을 확인했다.

- preregistered lifecycle 값: 일치
- 세 lifecycle 환경 변수를 제거한 rendered Compose: 동일
- same application image / same mock image: true

## 하지 않은 일

- 105초 VU 200 core, warm-up, k6 부하 실행: 0회
- policy effect, 성공 RPS, p95/p99, 503, timeout, transport failure의 비교·판정: 수행하지 않음
- MVC 실행, 새 metric/observer, pool/admission/timeout/resource 조정: 수행하지 않음

## artifact

`backend/experiments/results/experiment-1-19/preflight/`에 다음을 보존했다.

- `baseline-rendered-compose.yaml`, `remediation-rendered-compose.yaml`
- `controlled-compose-diff.txt`, `runtime-config-diff.json`
- `baseline-runtime-config.json`, `remediation-runtime-config.json`, `provenance.json`
- `collector-readiness.json`, `aggregator-schema.json`, `validity.json`, `preflight-summary.json`

## 결론

`READY_FOR_SIX_CORE_RUNS`는 **사전 확정한 여섯 core run을 시작할 수 있는 harness 상태**를 뜻한다. Fresh-First 정책이 성능·오류·연결 lifecycle을 개선한다는 결론은 아직 `NOT_RUN`이다.
