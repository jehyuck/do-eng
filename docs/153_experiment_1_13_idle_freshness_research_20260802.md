# Experiment 1-13 연구 — Idle Connection Freshness

## 확인 질문

Node mock의 keep-alive idle timeout보다 짧은 Reactor Netty `maxIdleTime`을 적용하면, peer가 먼저 종료한 pooled connection의 재획득과 연관된 AI PrematureClose를 제거하거나 유의하게 줄일 수 있는가?

## 선행 Evidence

- 기준 branch: `experiment/doeng-connection-close-attribution`
- 기준 result commit: `c271a949b81707f554899604d140af5a729b68ee`
- Experiment 1-12 core: `RUN-20260802-EXP112-CLEAN-001`, VALID
- AI PrematureClose request 108건
- connection-level PREMATURE_CLOSE 108건, 모두 REUSED_CHANNEL
- 같은 tuple의 최초 종료 주체는 mock 108건
- mock close가 ACQUIRED보다 먼저인 event 107건
- request ID와 connection lease의 1:1 귀속은 미완료이므로 최종 판정은 `PARTIALLY_ATTRIBUTED`

## Node mock keep-alive provenance

- mock Dockerfile base: `node:20-alpine`
- 실제 기존 mock image Node: `v20.20.2`
- `backend/experiment-mock/server.js`에서 `server.keepAliveTimeout`, `server.timeout`, `server.maxRequestsPerSocket`를 명시적으로 덮어쓰지 않는다.
- 같은 image에서 빈 `http.Server`를 생성해 확인한 runtime 기본값:
  - `keepAliveTimeout=5000ms`
  - `timeout=0`
  - `requestTimeout=300000ms`
  - `headersTimeout=60000ms`
  - `maxRequestsPerSocket=0`
- 실제 `/health` HTTP/1.1 응답:
  - `Connection: keep-alive`
  - `Keep-Alive: timeout=5`

따라서 이번 실험에서 mock effective keep-alive timeout은 5,000ms로 고정한다.

## Reactor Netty maxIdleTime 의미

현재 dependency는 Reactor Netty `1.0.28`이다. 해당 버전의 `ConnectionProvider.Builder`는 `maxIdleTime(Duration)`을 제공한다. 이 값은 pool에 반환되어 idle 상태인 connection의 최대 유휴 시간을 제한한다.

`maxIdleTime`은 active request의 응답 제한 시간이 아니다. 이미 lease되어 요청을 처리 중인 connection에는 response timeout처럼 적용되지 않는다. 따라서 AI의 정상 2초 응답이 4초 client idle freshness 설정 때문에 중단되어서는 안 된다.

## 현재 provider 상태

현재 `ExternalHttpClientConfig.buildProvider(...)`는 다음만 설정한다.

- maxConnections
- pendingAcquireMaxCount
- pendingAcquireTimeout
- 조건부 metrics

`maxIdleTime`은 설정하지 않는다. 따라서 baseline의 `maxIdleTimeMs=0`은 builder에 값을 전달하지 않아 기존 provider semantics를 유지해야 한다.

## 4,000ms 선택 근거

고정 관계는 다음 하나다.

```text
client maxIdleTime 4,000ms < mock keepAliveTimeout 5,000ms
```

목적은 mock이 5초 idle connection을 먼저 닫기 전에 client pool이 4초를 초과한 idle connection을 다음 acquire 후보에서 제외하도록 하는 것이다. 4초 외 값을 탐색하지 않는다.

## 연구 결론

`IMPLEMENTATION FEASIBLE`

- runtime 5초 전제가 확인됐다.
- Reactor Netty 1.0.28에서 조건부 maxIdleTime 적용 API가 존재한다.
- 기본값 0으로 기존 동작을 보존할 수 있다.
- active request timeout과 의미가 분리된다.

