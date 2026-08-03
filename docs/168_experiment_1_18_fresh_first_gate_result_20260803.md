# Experiment 1-18 결과 — Fresh-First Lifecycle Policy Deterministic Gate

작성일: 2026-08-03
판정: `GATES_PASSED`

## 기준과 범위

- 기준 branch: `experiment/doeng-fresh-first-lifecycle-policy`
- 기준 commit: `647a04320f66bc158952050260b1f6f88604ffea`
- Reactor Netty: 1.0.28 (dependency 변경 없음)
- 실행 범위: production configuration 구현과 test-local Reactor Netty gate만 수행
- 수행하지 않은 범위: Compose/runner, Docker application image build, VU load, A/B core, MVC 비교

## 변경 파일

- Production: `ExternalLeasingStrategy.java`, `ExternalServiceProperties.java`, `ExternalHttpClientConfig.java`, `application.yml`
- Test: `ExternalServicePropertiesTest.java`, `ExternalIdleFreshnessTest.java`, `FreshFirstLifecyclePolicyTest.java`
- 기존 active-response test의 server idle timeout은 2초 response와 같은 2초였던 fixture 경합을 제거하기 위해 20초로만 변경했다. production timeout이나 pool policy는 변경하지 않았다.

## 실행 환경과 명령

로컬 셸에는 Java 실행 경로가 없어 host Gradle은 시작하지 못했다. 따라서 Eclipse Temurin JDK 11 Docker container에서 같은 source volume을 사용해 test를 실행했다. 이는 application image build나 Compose 실행이 아니다.

```text
docker run --rm -v "${PWD}:/workspace" -v "$env:USERPROFILE\\.gradle:/root/.gradle" \
  -w /workspace eclipse-temurin:11-jdk ./gradlew test \
  --tests com.example.doenggameflux.config.ExternalServicePropertiesTest \
  --tests com.example.doenggameflux.config.ExternalIdleFreshnessTest \
  --tests com.example.doenggameflux.config.FreshFirstLifecyclePolicyTest \
  --no-daemon
```

최종 실행: `BUILD SUCCESSFUL`, 15 tests, failures 0, errors 0. `FreshFirstLifecyclePolicyTest`은 4 tests, failures 0, errors 0이었다.

## Gate A — baseline preservation

통과.

- 기본 property: FIFO / maxIdleTime 0ms / background eviction 0ms.
- 기본 validation 통과 및 baseline idle reuse를 확인했다.
- 실행 channel: A와 B가 동일 channel `...f9b3340f`를 사용했다.
- FIFO/0/0에서는 `.fifo()`, `.maxIdleTime(...)`, `.evictInBackground(...)`를 호출하지 않는 조건부 builder 구조를 유지했다.

## Gate B — LIFO leasing

통과.

- test-local provider: LIFO, maxConnections 2, maxIdle 미설정, background eviction 비활성.
- latch와 `Sinks.One`으로 A와 B를 별도 channel에 동시 점유시킨 뒤 A release → B release 순서를 고정했다.
- A channel: `...8016fac6`
- B channel: `...53fe1184`
- C channel: `...53fe1184`
- A와 B는 서로 달랐고, C는 가장 최근 release된 B를 사용했다. 시간 근접성이나 `Thread.sleep()`으로 release 순서를 추정하지 않았다.

## Gate C — background idle eviction

통과.

- test-local provider: LIFO / maxIdleTime 3,000ms / eviction interval 1,000ms.
- server idle timeout: 20초로 client policy보다 길게 설정.
- response 완료와 pool release 뒤에만 기존 channel `closeFuture`를 등록해, 추가 acquire 없이 close를 관찰했다.
- evicted channel: `...9727c383`; 다음 request channel: `...7b78f874`.
- release-to-close: 3,991ms. 3,000ms보다 이르지 않았고, 사전 고정한 6초 bound 안에 close됐다.
- 6초 bound는 3초 eligibility + 최대 1초 background scan + local scheduler 여유 2초다. 이 값은 결과 후 조정하지 않았다.

## Gate D — active response protection

통과.

- 동일 remediation provider에서 server가 2초 뒤 body를 반환했다.
- 실제 active response 시간: 2,015ms.
- body `ok`가 정상 완료됐으며 response release 전 channel close는 관찰되지 않았다.

## Gate E — retry invariance

통과.

production Java source 검색 결과 이번 diff에는 `.disableRetry(`, `.retry(`, `.retryWhen(`, `Retry.` 추가가 없었다. 기존 Reactor Netty transport retry 기본 동작과 application retry는 변경하지 않았다.

## Controlled diff 확인

허용된 변경만 존재한다.

- leasing strategy property와 default FIFO 추가
- background eviction interval property와 default 0 추가
- LIFO일 때만 `builder.lifo()` 호출
- positive max idle/eviction interval일 때만 기존 및 신규 lifecycle API 호출

변경되지 않은 항목: pool max/pending, timeout, admission, controller/business chain, server/mock, retry, dependency.

## 원시 근거와 한계

- Java 11 test report: `backend/doEngGameFlux/build/test-results/test/TEST-com.example.doenggameflux.config.FreshFirstLifecyclePolicyTest.xml`
- Gate artifact: `backend/doEngGameFlux/build/experiment-1-18/` (`gates.json`, `events.jsonl`, `channels.csv`, `validity.json`)
- channel ID는 test-local loopback run의 일회성 식별자이며 production workload 결과가 아니다.
- Gate B/C/D는 policy API가 기대한 local lifecycle 동작을 증명하지만, stale `PrematureClose`가 실제 VU workload에서 감소한다는 성능·운영 claim은 아직 증명하지 않는다.
- 이 문서는 A/B 실행, 채택 선언, rollback을 수행하지 않는다.

## 최종 판정

`GATES_PASSED`

production configuration, Gate A~E, 관련 Java 11 tests, controlled diff가 모두 통과했다. 다음 허용 작업은 사전등록된 A/B를 실행할지 사용자 승인으로 결정하는 것이며, 이 결과만으로 정책을 채택하지 않는다.
