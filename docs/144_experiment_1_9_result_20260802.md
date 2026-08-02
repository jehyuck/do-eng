# Experiment 1-9 Result

## Branch

`experiment/doeng-reactive-overload-control`

## Source commit

- `4eb3495` — `실험: reactive admission 관찰 및 강제 모드 추가`
- `7f823a8` — `실험: overload control runner 인자 연속성 수정`

기준 pool-isolation commit은 `e44768b`이며, 기존 작업 tree의 무관한 변경은 source/result commit에 포함하지 않았다.

## Result commit

이 문서와 ledger addendum을 포함하는 별도 문서 commit으로 기록한다.

## 공식 자료 결론

Spring WebFlux는 non-blocking publisher와 reactive 실행 모델을 제공하지만 전체 HTTP request path의 동시성 예산을 자동으로 정하지 않는다. Reactor Netty connection pool은 outbound channel acquire와 pending을 제한하는 자원 경계이지, body/TOKEN/AI/STORAGE/DB 전체의 admission 정책은 아니다. 따라서 전체 pipeline을 lazy하게 감싸는 애플리케이션 admission 경계가 별도로 필요하다.

## 확인된 capacity 손실

VALID OBSERVE 3회에서 limit을 강제하지 않자 전체 admission max in-flight가 1,435~1,848까지 증가했고 `wouldReject`가 약 20,039~20,350이었다. 세 run 모두 shared provider active가 400에 도달했으며 pending max는 1,043~1,892였다. HTTP 500과 client timeout도 반복됐지만 규모는 run마다 크게 달랐다. 이는 non-blocking이라는 사실만으로 full-path overload가 자동 해소되지 않음을 보여준다.

## 수정한 항목

- admission 설정을 명시적 `OFF|OBSERVE|ENFORCE`로 분리했다.
- `Mono.defer → action supplier → doFinally release` 경계를 전체 request path에 적용했다.
- OBSERVE에서는 한도를 넘겨도 실행하고 `wouldReject`만 기록한다.
- ENFORCE에서는 limit 초과 시 action supplier를 호출하지 않고 `AiCapacityExceededException`을 발생시킨다.
- admission 503에 `Retry-After: 1`을 추가했다.
- mode, configured limit, in-flight/max, started/completed/rejected/released/cancelled/leak/would-reject metric과 endpoint snapshot을 추가했다.
- HTTP 503 admission과 downstream 503/4xx/5xx, HTTP500, timeout, connection error를 client outcome에서 분리했다.
- lazy rejection, success/error/cancel release, OBSERVE over-limit, CAS race, handler header 테스트를 추가했다.

## 변경하지 않은 항목

WebFlux business chain, TOKEN→AI→STORAGE→DB 순서, SHARED pool topology, maxConnections 400, pending 800, DB pool 10, timeout, retry 정책, scheduler, Base64, resource/CPU/memory, workload/VU, MVC, queue, Resilience4j, adaptive concurrency는 변경하지 않았다.

## OBSERVE 결과

| Run | validity | successful RPS (HTTP200/105s) | accepted p95/p99 | max in-flight | HTTP500 | timeout | pool active/pending max | drain |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| OBSERVE-002 | VALID | 104.97 | 9,266 / 9,835 ms | 1,576 | 8,049 | 1,595 | 400 / 1,419 | 6,014 ms |
| OBSERVE-003 | VALID | 132.19 | 8,541 / 9,629 ms | 1,435 | 6,201 | 589 | 400 / 1,043 | 6,007 ms |
| OBSERVE-004 | VALID | 6.65 | 9,617 / 9,931 ms | 1,848 | 15,053 | 4,608 | 400 / 1,892 | 9,000 ms |

세 OBSERVE run 모두 `rejected=0`, permit leak 0, drain 완료였다. 그러나 successful goodput과 failure tail의 반복성이 낮아 sustainable goodput을 단일 값으로 확정할 수 없다.

## 선택한 concurrency limit과 근거

`320`을 사전 등록했다([limit registration](143_experiment_1_9_limit_preregistration_20260802.md)). 기존 FULL_PATH320 결과에서 이미 사용한 비교 가능한 경계이며, 새 OBSERVE raw에서 확인된 pool active/pending collapse를 허용하는 1,435~1,848를 그대로 limit으로 선택하지 않았다. 320이 production optimum이라는 주장은 하지 않는다.

## ENFORCE 결과

| Run | validity | successful RPS | admission503 | HTTP500 | timeout | connection error | accepted p95/p99 | pool active/pending max | drain |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ENFORCE-001 | VALID | 46.12 | 6,220 | 24 | 1,588 | 6,863 | 8,916 / 9,778 ms | 320 / 18 | 6,012 ms |
| ENFORCE-002 | VALID | 123.14 | 7,737 | 0 | 0 | 0 | 4,238 / 8,285 ms | 320 / 3 | 3,006 ms |
| ENFORCE-003 | VALID | 123.02 | 7,724 | 0 | 0 | 0 | 2,766 / 5,687 ms | 321 / 3 | 3,004 ms |

세 run 모두 configured limit 320, max observed in-flight 320, permit leak 0, rejected request의 downstream subscription 0(unit test), drain 완료였다. ENFORCE-002/003은 uncontrolled HTTP500·timeout·connection error 없이 explicit admission 503만 overload 결과로 남겼다. ENFORCE-001은 동일 조건의 VALID run이지만 client/transport failure와 HTTP500이 남아 run 간 변동성을 드러냈다.

## successful goodput 비교

OBSERVE successful RPS는 6.65~132.19, ENFORCE는 46.12~123.14였다. ENFORCE-002/003의 123 RPS는 OBSERVE-002/003보다 높고 OBSERVE-004보다 훨씬 높지만, OBSERVE 자체의 변동폭과 ENFORCE-001의 실패를 고려하면 95% 보존 조건을 모든 반복에서 충족했다고 확정할 수 없다.

## 503 분류

ENFORCE에서 발생한 503은 response body `AI_CAPACITY_EXCEEDED`를 가진 명시적 admission 503으로 분류했다. downstream 503은 0건이었다. OBSERVE에서는 admission 503이 0건이어야 하며 실제로 0건이었다. 따라서 overload rejection과 downstream/application failure를 raw outcome에서 분리할 수 있다.

## pool 결과

OBSERVE에서는 shared provider active가 400에 닿고 pending이 800 설정값 부근 또는 초과까지 늘었다. ENFORCE-002/003에서는 active가 320~321, pending max가 3으로 낮아졌다. ENFORCE-001도 pending max 18이었지만 connection error가 많아 보호만으로 모든 run의 transport outcome을 보장하지 못했다.

## 최종 분류

**B — PROTECTION ONLY**

현재 증거는 전체 path admission이 실제로 limit을 적용하고 pool pressure와 uncontrolled failure를 크게 줄일 수 있음을 지지한다. 하지만 세 ENFORCE run 모두에서 uncontrolled failure가 0이 아니었고, successful goodput/accepted latency가 run마다 크게 달라 `CAPACITY RECOVERED AND PROTECTED(A)`를 확정할 정도로 sustainable capacity가 재현되지 않았다. 따라서 이번 실험은 capacity 회복이 아니라 overload protection의 증거로만 분류한다.

## 다음 단계 후보

실험 1-9는 여기서 중단한다. 추가 limit sweep, pool 변경, retry/queue/adaptive concurrency, MVC 재실행은 하지 않는다. 후속 작업이 필요하다면 한 가지 diagnostic 질문(ENFORCE-001의 transport failure와 ENFORCE-002/003의 안정성 차이를 설명하는 단일 계측)을 별도 계획으로 사전 등록해야 하며, 현재 결과만으로 application optimization을 시작하지 않는다.

## Validity와 Claim 범위

`RUN-20260802-EXP19-OBSERVE-001`은 collector timeout 2건으로 INVALID 처리하고 raw를 보존했다. 최종 비교에는 OBSERVE 002~004와 ENFORCE 001~003의 VALID run만 포함했다. 성능 결과는 이 frozen workload, shared pool, 2 CPU/3 GiB, mock latency 환경에 한정하며 WebFlux 일반 우위나 production optimum limit을 주장하지 않는다.
