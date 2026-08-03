# Experiment 1-17 — Fresh-First Lifecycle Policy Decision

## DECISION

`READY_FOR_CONTROLLED_IMPLEMENTATION`

## SELECTED POLICY

`FRESH_FIRST_LIFECYCLE_POLICY_V1`

## CONFIGURATION

```text
BASELINE: FIFO default, maxIdle=0, background eviction disabled
REMEDIATION: LIFO, maxIdle=3000ms, background eviction=1000ms
maxLifeTime/custom predicate: unset
transport retry: Reactor Netty default unchanged
application retry/server keep-alive: unchanged
```

## EVIDENCE

Experiment 1-13의 4초 maxIdle 단독 정책은 stale reused PrematureClose를 제거하지 못했다. Experiment 1-16의 fixed race에서는 client closeFuture 완료 뒤 pool이 old closed channel을 8/8 제외했다. 이 두 Evidence는 오래 idle한 connection 선택을 줄이고 acquire-only eviction 의존을 낮추는 복합 정책을 한 번 검증할 근거가 된다.

## BOUNDED INFERENCE

peer close와 client close reflection 사이의 경계가 stale reuse와 연결될 수 있다는 수준이다. FIFO, LIFO, 3초, 1초, Reactor Netty bug의 개별 인과성은 확정하지 않는다.

## SUCCESS GATE

baseline/remediation 각 3 VALID run, baseline mechanism 2/3 이상 재현, remediation stale reused PrematureClose 0/3, AI PrematureClose 90% 이상 감소, AI transport HTTP 500 0/3, duplicate handler 0, 새 uncontrolled failure 없음과 guardrail 통과가 모두 필요하다.

## FAILURE GATE

deterministic gate·validity·controlled diff 실패, stale reused mechanism 잔존, AI transport HTTP 500 잔존, 90% 감소 미달, duplicate handler, 새 uncontrolled failure, 성능/운영 guardrail 실패 중 하나면 채택하지 않는다.

## ROLLBACK

FIFO default, maxIdle 미설정, background eviction disabled로 복귀한다.

## NEXT ALLOWED STEP

production implementation과 deterministic gates를 하나의 사전등록 계약으로 수행하고, gates 통과 시에만 6-run A/B를 실행할 수 있다.

## HARD STOP

이번 단계에서는 implementation, deterministic gate, image build, VU 부하, MVC 비교를 실행하지 않았다. 이 문서 이후 자동 실행하지 않는다.
