# Experiment 1-14 Remediation Decision

## DECISION

`INSUFFICIENT_EVIDENCE`

현재 evidence는 stale pooled channel reuse와 4,000ms maxIdle 단독 정책의 실패를 확인했지만, 다음 lifecycle policy의 수치와 조합을 정할 만큼 request-bound server/client idle boundary를 측정하지 못했다. 따라서 remediation 구현과 VU 부하 실행을 시작하지 않는다.

## SELECTED POLICY

선택 정책 없음.

후보 우선순위는 `LIFO + derived maxIdleTime + evictInBackground`이지만, `derived` 값과 eviction interval을 현재 원시 artifact로 산출할 수 없으므로 remediation policy로 확정하지 않는다.

## REJECTED ALTERNATIVES

- server keep-alive와 client 정책 동시 변경: 두 경계를 함께 바꿔 인과를 분리할 수 없음.
- application retry: Reactor Netty 1.0.28의 pre-send retry-once가 이미 기본 활성화되어 있고, POST requestId–lease 결합이 불완전함.
- maxLifeTime: peer idle expiry가 아니라 connection age를 바꾸는 별도 가설임.
- pooling off/newConnection: connection reuse를 제거해 churn이라는 큰 교란변수를 도입함.
- Reactor Netty upgrade: lifecycle policy 평가와 version 변경을 혼합함.

## EVIDENCE

- 현재 provider는 공유 `doeng-external`, pool 400/pending 800, explicit leasing strategy 없음이다.
- Reactor Netty 1.0.28 default leasing strategy는 FIFO이며, current source는 `.lifo()`, `.maxLifeTime()`, `.evictInBackground()`, custom predicate를 호출하지 않는다.
- Experiment 1-13 6 VALID core에서 4,000ms maxIdle은 stale reused pre-send AI premature close를 제거하지 못했다: baseline 78건, remediation 168건.
- remediation 168건은 모두 reused channel이며 166건은 mock close가 acquire보다 먼저 관측되고 `REQUEST_SENT`가 없다.
- mock response finish와 client release는 각각 기록되지만, 실패 lease의 `AI_REQUEST_CHANNEL_BOUND`가 누락되어 request-level clock difference를 계산할 수 없다.
- current AI call은 JSON body의 POST이며 source-level application retry는 없다. Reactor Netty transport retry-once는 pre-send connection reset에 기본 적용된다.

## REMAINING RISK

- 지금 LIFO·maxIdle·background eviction을 함께 적용하면, 4,000ms 실패가 clock-boundary 때문인지 lazy eviction 때문인지 FIFO 선택 때문인지 구분할 수 없다.
- post-send POST failure는 mock handler/DB side effect 중복 위험을 가진다. 현재 artifact는 pre-send failure 표본을 보이지만 모든 retry attempt의 request-level 완전성은 보장하지 않는다.
- Node mock의 5초 keep-alive는 실제 AI/S3 정책을 대표하지 않는다.

## NEXT EXPERIMENT

부하 없는 deterministic one-connection diagnostic 1회만 허용한다.

단일 변경은 **AI requestId를 `REQUEST_PREPARED` 이전부터 channel/lease에 결합하고, 같은 requestId로 response-received, response-completed, released를 기록하는 관측 보강**이다. mock의 existing response-finished/close event와 결합해 server response finish → client release 분포와 다음 acquire 시점을 직접 계산한다. pool size, timeout, retry, admission, lifecycle configuration, workload는 변경하지 않는다.

## HARD STOP

이 문서 이후 자동 remediation 구현, idle value sweep, VU 부하 실행, application retry 추가, server keep-alive 변경, pool/resource tuning, Reactor Netty upgrade를 수행하지 않는다.

다음 deterministic diagnostic이 위 결합을 완성하지 못하면 lifecycle remediation도 진행하지 않고 `INSUFFICIENT_EVIDENCE`를 유지한다.
