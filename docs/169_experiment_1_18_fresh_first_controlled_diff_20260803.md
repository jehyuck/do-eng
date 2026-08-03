# Experiment 1-18 — Fresh-First Lifecycle Policy Controlled Diff

작성일: 2026-08-03
기준 commit: `647a04320f66bc158952050260b1f6f88604ffea`

| 항목 | Baseline | 구현한 remediation 경로 | Source path | Test evidence | 허용 여부 |
|---|---|---|---|---|---|
| leasing strategy | 명시 호출 없음, Reactor Netty 기본 FIFO | `LIFO`일 때만 `builder.lifo()` | `ExternalHttpClientConfig.java` | Gate B | 허용 |
| max idle | 0이면 builder 미호출 | 양수일 때만 기존 `maxIdleTime` 적용 | `ExternalHttpClientConfig.java` | Gate A/C/D | 허용 |
| background eviction | 0이면 builder 미호출 | 양수일 때만 `evictInBackground` 적용 | `ExternalHttpClientConfig.java` | Gate C/D | 허용 |
| configuration binding | max-idle만 존재 | leasing strategy와 eviction interval 추가 | `ExternalServiceProperties.java`, `application.yml` | property tests | 허용 |
| validation | negative max-idle 거부 | null strategy와 negative eviction도 fail-fast | `ExternalServiceProperties.java` | property tests | 허용 |

## Baseline preservation

`FIFO / 0 / 0`은 명시적 `.fifo()`, `.maxIdleTime(...)`, `.evictInBackground(...)` 호출 없이 builder를 구성한다. 따라서 기존 provider 기본 lifecycle 의미를 별도 API 호출로 덮어쓰지 않는다.

## 비변경 확인

- Pool max connection / pending acquire count: 변경 없음
- Connect, response, pending acquire timeout: 변경 없음
- Admission, semaphore, bulkhead, rate limiter: 변경 없음
- Retry: `.disableRetry`, `.retry`, `.retryWhen`, `Retry.` 추가 없음
- Server/mock, Compose, runner, workload, VU: 변경·실행 없음
- Controller, service business logic, reactive chain, scheduler: 변경 없음
- Spring Boot, Reactor Netty, dependency: 변경 없음

## Test-only 변경

- `FreshFirstLifecyclePolicyTest`는 loopback server, local provider, latch/Sink와 channel closeFuture로 Gate A~D를 검증한다.
- `ExternalServicePropertiesTest`는 새 defaults, valid remediation values, null/negative validation을 검증한다.
- `ExternalIdleFreshnessTest`의 active-response fixture는 2초 response와 서버 idle timeout이 동률이던 경합을 제거하기 위해 server idle timeout만 20초로 늘렸다. production 설정에는 영향을 주지 않는다.

## 판정

허용하지 않은 production 변경은 확인되지 않았다. 이 diff는 configuration implementation과 deterministic verification에 한정되며, A/B 성능 결과나 정책 채택 근거가 아니다.
