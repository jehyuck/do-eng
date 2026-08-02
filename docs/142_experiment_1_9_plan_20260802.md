# Experiment 1-9 계획: Reactive Capacity Recovery and Overload Control

## 확인하려는 질문

현재 SHARED outbound pool(400 connections, pending 800) 조건에서 WebFlux REST 경로가 실제로 유지할 수 있는 전체 요청 동시성을 먼저 관찰하고, 그 범위를 넘는 요청을 전체 pipeline 구독 전에 명시적인 503으로 보호할 수 있는가?

## 실험 목적

HTTP 500을 단순히 503으로 바꾸는 것이 아니라, 실제 sustainable goodput과 accepted latency를 보존하면서 overload를 예측 가능한 admission 결과로 분리하는지 확인한다.

## 가설

1. WebFlux와 Reactor Netty는 non-blocking 실행 모델과 outbound pool을 제공하지만 전체 request concurrency의 상한을 자동으로 정하지 않는다.
2. 관찰 모드에서 실제 전체 경로 in-flight와 기존 FULL_PATH320 결과를 함께 보면 하나의 고정 concurrency limit을 사전 등록할 수 있다.
3. 같은 binary에서 ENFORCE 모드만 켜면 한도를 넘는 요청은 body/TOKEN/AI/STORAGE/DB를 구독하지 않고 503으로 빠르게 거절되며, uncontrolled 500과 pool pressure를 줄일 수 있다.

## 기준 조건

- 기준 branch/commit: `experiment/doeng-outbound-pool-isolation` / `e44768b`
- 새 branch: `experiment/doeng-reactive-overload-control`
- WebFlux, SHARED pool
- app 2 CPU / 3 GiB, DB pool 10
- shared HTTP pool max 400, pending acquire max 800
- AI delay 2,000 ms, storage delay 100 ms
- frame/reconnect 1 s, duration 105 s, client timeout 10 s
- 동일 fixture, auth/token, DB/storage contract, fresh JVM

## 변경 조건

소스 변경은 admission mode를 `OFF|OBSERVE|ENFORCE`로 명시하고, 전체 request path를 계수하는 관찰/강제 경계를 추가하는 것뿐이다. 풀, timeout, retry, scheduler, workload, resource는 변경하지 않는다.

실행에서는 동일 binary에 대해 `mode`와 사전 등록한 `limit`만 변경한다.

## 유지 조건

`DOENG_EXTERNAL_POOL_MODE=SHARED`, pool budget, DB pool, mock delay, client pacing, fixture, token, request timeout, drain 30 s, DB/container monitor, load-stop snapshot, consistency verification을 모든 run에 고정한다. application continuous snapshot, mock continuous polling, JFR/NMT는 사용하지 않는다.

## 측정 지표

- admission mode, configured limit, in-flight, max observed
- started, completed, rejected, released, cancelled, permit leak, would reject
- successful goodput, HTTP 200, explicit admission 503, downstream 4xx/5xx, application 500, connection error, timeout, client abort
- accepted p95/p99(빠른 admission 503 제외)
- stage started/duration/in-flight, pool active/pending, CPU/memory, DB active/pending, mock in-flight, drain 결과

## 실행 순서

1. 본 계획과 source audit/research 문서를 먼저 고정한다.
2. Docker JDK 11 build, unit/context/endpoint/smoke/parse/config gate를 통과시킨다.
3. OBSERVE 1회로 실제 in-flight와 failure/latency/pool 관계를 수집한다. 이 run은 limit 선택용이며 개선 결론을 내리지 않는다.
4. 이전 FULL_PATH320 결과와 OBSERVE 결과를 사용해 하나의 limit을 사전 등록한다. 동일 실험 안에서 limit sweep을 하지 않는다.
5. crossover 순서로 OBSERVE 3회와 ENFORCE 3회를 수행한다. 각 run은 fresh JVM과 warm-up 뒤 실행한다.
6. measurement validity와 system outcome을 분리해 결과와 raw를 보존한다.

## 판정 기준

- A: 확인된 capacity 손실을 admission으로 보호하고 goodput/accepted latency가 유지됨.
- B: 500은 줄지만 sustainable capacity 회복 근거가 부족함.
- C: pool/latency/goodput이 개선되지 않거나 limit이 부적절함.
- F: provenance, collector, lifecycle, workload 계약이 깨진 run.

ENFORCE의 성공 조건은 uncontrolled HTTP 500=0, pool acquire/connection error=0, permit leak=0, drain 완료, explicit admission 503만 overload 결과로 나타남, successful goodput이 OBSERVE sustainable goodput의 95% 이상, accepted p95와 pending이 OBSERVE보다 낮음이다.

## 중단 규칙

자동 limit sweep, queue 추가, Resilience4j/adaptive concurrency 도입, pool 증설/분리, HTTP/2, retry, MVC 재실행은 하지 않는다. A가 확인될 때만 tuned MVC/WebFlux 비교를 후속 후보로 기록한다.

## 결과 저장 및 provenance

각 run은 `experiment/results/<RUN-ID>/`에 raw, run-config, verification, provenance, container, DB, mock, drain, ledger를 보존한다. 기존 Experiment 1-8 raw와 섞지 않는다. 소스 변경 commit과 결과 문서 commit은 별도로 만든다.

## 사용자 판단 필요 사항

관찰 후 선택할 limit의 SLO 경계가 기존 문서의 accepted p95 기준과 일치하는지 결과 문서에 명시하고, 측정하지 않은 scheduler queue/body decode/permit holding 구간은 추정으로 채우지 않는다.
