# WebFlux 이미지 payload 특성화

## 질문과 목적

고정된 `SERVICE3S` WebFlux 요청 흐름에서 실제 이미지 payload 처리가 CPU와 allocation 증거에 나타나는지 확인한다. 이 문서는 튜닝이나 매트릭스 실험이 아니라 단일 특성화 실행을 기록한다.

## Evidence

- Source HEAD: `407e380f0fdb91a167685ebc8300b544039b3d75`
- Clean local branch: `profile/image-payload-407e`
- Raw run: `experiment/results/WEBFLUX-IMAGE-PAYLOAD-PROFILE-002`
- Canonical index: `experiment/results/WEBFLUX-IMAGE-PAYLOAD-PROFILE/README.md`
- Source aggregate SHA256: `2f93279f9d8dab7b746b2d90c3cd9df7f98e6c9a71beef64d8be1b352a2f1929`
- Fixture: `image/arc.jpg`, 265745 bytes, `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- Runtime: Java 11.0.31; JFR source/copied size was 15976541/15976541 bytes.

## 실행 유효성 및 결과

`WEBFLUX-IMAGE-PAYLOAD-PROFILE-002`는 유효한 실행이다. 5406건의 시작 요청과 완료 요청을 기록했고, 성공 응답은 3310건, 실패 응답은 2096건이었다. connection error는 0건, client timeout은 2087건, p50은 2469ms, p95는 8425ms, p99는 9795ms, 최댓값은 10002ms, `maxInFlight`는 540, 미완료 요청은 0건이었다. Mock drain은 3005ms에 완료됐다.

## 특성화 관찰

JFR execution sample에서 Jackson JSON parser/generator, Base64 decoder, `ImagePayloadDecoder`, Reactor, Netty 및 애플리케이션 프레임이 반복적으로 관찰됐다. payload 관련 family는 early, middle, late window 모두에서 나타났다. allocation sample에는 Jackson byte/text builder, array copy 연산, Netty composite byte buffer가 포함됐다. recording에는 garbage collection event 105건과 heap-summary event 210건이 포함됐다.

## 분류

현재 문서의 상태는 다음과 같다.

```text
PROFILE VALID
VERDICT NOT YET CLOSED
```

관찰된 payload 관련 CPU 및 allocation activity는 별도 통제 후속 검증의 대상이 될 수 있지만, 최종적인 material-cost verdict가 확정된 것은 아니다.

## 확인된 사실

- detached-worktree preflight failure는 harness topology 문제인 `DETACHED_HEAD_BRANCH_NULL`이었다.
- clean local branch를 사용해 environment capture가 통과했다.
- 단일 characterization workload가 유효한 accounting과 검증된 JFR capture를 남겼다.
- application과 dependency identity가 raw runtime identity artifact에 기록돼 있다.

## 아직 확정되지 않은 사항

- payload processing이 MVC collapse의 유일한 원인인지
- 특정 low-level component가 단독 원인인지
- 최적화 효과가 있는지
- WebFlux의 보편적인 우위가 있는지
- payload가 최종적으로 `PAYLOAD_COST_MATERIAL_CANDIDATE`로 확정될 수 있는지

## Claim boundary

허용되는 표현은 다음과 같다.

> 유효한 WebFlux 실행에서 payload 관련 processing activity가 반복적으로 관찰됐으며, 별도 통제 후속 검증의 대상이다.

Jackson/Base64/Netty/image decoding 중 하나만을 root cause로 단정하거나, 성능 개선 효과를 주장해서는 안 된다.

## 다음 판단

추가 workload는 실행하지 않았다. 후속 작업이 필요하다면 별도의 승인된 controlled profiling 또는 comparison 설계를 먼저 수립해야 한다.
