# Experiment 1-18 — Fresh-First Lifecycle Policy 구현 및 Deterministic Gate 계획

작성일: 2026-08-03
상태: 구현 및 deterministic gate 수행 전 사전 계획

## 확인하려는 질문

사전등록한 `FRESH_FIRST_LIFECYCLE_POLICY_V1`을 baseline의 기본 provider 의미를 바꾸지 않고 설정 가능한 형태로 구현할 수 있는가? 또한 LIFO 선택, background idle eviction, active response 보호, retry 불변성을 test-local deterministic gate로 검증할 수 있는가?

## 구현 범위

- `ExternalLeasingStrategy` enum과 `ExternalServiceProperties`의 leasing/eviction property를 추가한다.
- provider builder에는 LIFO, 양수 max-idle, 양수 background eviction만 조건부로 적용한다.
- 기본값은 FIFO / 0ms / 0ms로 유지하며 FIFO·0ms에는 lifecycle builder API를 호출하지 않는다.
- Java 11에서 관련 unit test와 local Reactor Netty integration gate를 실행한다.

## 고정 정책과 baseline

| 구분 | leasing strategy | maxIdleTime | background eviction |
|---|---:|---:|---:|
| Baseline | Reactor Netty 기본값(FIFO) | builder 미호출 | builder 미호출 |
| FRESH_FIRST_LIFECYCLE_POLICY_V1 | LIFO | 3,000ms | 1,000ms |

maxLifeTime, custom eviction predicate, retry, timeout, pool 용량, admission, 서버/mock, business chain, dependency는 변경하지 않는다.

## Property contract

- `leasingStrategy`: 기본 `FIFO`, null은 fail-fast한다.
- `maxIdleTimeMs`: 기본 0, 음수는 fail-fast한다.
- `backgroundEvictionIntervalMs`: 기본 0, 음수는 fail-fast한다.
- YAML binding: `DOENG_EXTERNAL_LEASING_STRATEGY`, `DOENG_EXTERNAL_MAX_IDLE_TIME_MS`, `DOENG_EXTERNAL_EVICTION_INTERVAL_MS`.

## Gate 설계

### Gate A — baseline preservation

기본 property가 FIFO / 0 / 0인지, validation이 통과하는지, local provider가 기존처럼 idle connection을 재사용하는지를 확인한다. FIFO와 0ms 조건에서는 lifecycle API를 강제로 호출하지 않는다.

### Gate B — LIFO leasing

test-local server에서 A와 B request를 동시에 점유시켜 서로 다른 channel을 확보한다. server-side `Sinks.One`과 latch로 A 응답을 먼저, B 응답을 나중에 해제하고 각각의 client pool release를 관찰한다. 이후 C request가 B channel(가장 최근 release)을 사용하는지 channel ID로 확인한다. release 순서를 추정하기 위한 `Thread.sleep()`은 사용하지 않는다.

### Gate C — background idle eviction

LIFO / 3,000ms / 1,000ms provider와 충분히 긴 server idle timeout을 사용한다. response 완료 뒤 client pool release를 확인하고, 추가 acquire 없이 기존 channel의 `closeFuture`를 관찰한다. close가 release 후 3,000ms보다 이르면 실패이며, release 후 고정 6초 내 close되지 않아도 실패다. 6초는 3초 idle eligibility + 최대 1초 scan 간격 + local scheduler 여유 2초를 사전 고정한 bound이며, 결과에 따라 조정하지 않는다. close 후 다음 request가 새 channel을 쓰는지도 확인한다.

### Gate D — active response protection

동일 remediation provider로 2초 지연 response를 처리한다. body가 정상 완료되고 active response 중 premature close가 없는지 확인한다.

### Gate E — retry invariance

production source diff와 검색으로 `.disableRetry`, `.retry`, `.retryWhen`, `Retry.` 추가가 없는지 확인한다.

## 실행과 저장

- 관련 Gradle tests만 실행하고 Docker JDK 11 test gate를 실행한다.
- test-local server/provider만 사용한다. Compose, runner, Docker image build, VU load, MVC 비교는 실행하지 않는다.
- Gate 결과와 channel/timing evidence는 `docs/168`에, 허용 범위 diff는 `docs/169`에 기록한다.
- 실행 원장은 `docs/11_run_ledger.md`에 설정 구현 및 deterministic gate 항목으로 남긴다.

## 판정

Gate A~E, 관련 tests, Java 11 Docker test gate, controlled diff를 모두 통과하면 `GATES_PASSED`다. 하나라도 test/gate 실패면 `GATE_FAILED`이며 값과 timeout을 즉시 변경하지 않는다. baseline/branch/dependency 또는 artifact 조건의 무결성을 확인할 수 없으면 `INVALID`다.

## Hard stop

이번 작업은 구현·deterministic gate·문서화·commit/push에서 종료한다. Compose/runner, A/B load, Docker application image build, VU 실행, MVC 실행, 추가 값 탐색, 정책 채택 선언은 다음 작업으로 넘긴다.
