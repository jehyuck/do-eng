# Exp153 Sink Dispatcher Controlled A/B 계획

## 상태

이 문서는 실행 전 사전등록 및 하네스 검증 계획이다. 본 작업에서는 부하 측정과 성능 해석을 수행하지 않는다.

## 질문

동일한 provider pool, 외부 Mock, DB, workload 조건에서 bounded Sink Dispatcher가 기존 직접 reactive 체인보다 provider pending, timeout, cancellation 및 transport failure를 줄이는지 확인한다.

`Sink Dispatcher`가 더 빠르거나 최적 concurrency라는 주장은 이 실험으로 사전 확정하지 않는다.

## 비교 조건

| Cell | Source | 경로 |
|---|---|---|
| A | `experiment/exp151-admission-gate-capacity` (remote ref 확인 필요) | 기존 직접 reactive 호출 |
| B | `experiment/exp152-sink-dispatcher@cf5b36ad38928d55eab131d1328dc85ccff0ad3b` | bounded dispatcher |

Cell B 고정값은 `doeng.dispatcher.global-deadline=10s`, token `100/2000`, AI `400/800`, storage `100/200`이다. A/B의 pool, workload, Mock, DB, resource, timeout, fixture, actor와 collector는 동일하게 렌더링되어야 한다.

## Deadline 분리

서버 global deadline은 10초, client timeout은 15초로 고정한다. 결과에서는 server-side 504, client timeout, provider response timeout, pending-acquire timeout을 별도 분류한다.

## 순서와 반복

`A1 → B1 → B2 → A2 → A3 → B3` 순서로 각 조건 3회 유효 run을 확보한다. warm-up은 각 run의 fresh recreate 전에 별도로 수행한다. invalid run은 원인을 기록하고 해당 번호만 대체한다.

## 사전 smoke

실제 본 측정 전에 다음 두 smoke를 별도 결과로 보존한다.

- queue-full: dispatcher concurrency=1, queue=1인 smoke override에서 503와 `DispatcherQueueRejectedException`을 확인한다.
- deadline: global deadline을 짧게 둔 smoke override에서 504와 `DispatcherDeadlineExceededException`, deadline phase를 확인한다.

Smoke override는 본 실험 설정을 변경하지 않으며 본 측정 결과에 포함하지 않는다.

## 관측 및 accounting

Client outcome, provider pool, dispatcher queue/active/wait/events, application resource, DB integrity를 수집한다. Dispatcher별 accounting은 `enqueued = completed + failed + cancelled + deadline + queue + active` 관계를 확인하되 중복 이벤트 정의는 결과 문서에 명시한다. 종료 시 queue와 active가 0이 아니면 해당 run은 유효 성능 결과로 사용하지 않는다.

## 판정 범위

반복적으로 provider pending·timeout·transport failure가 줄고 성공 RPS가 유지/개선되는 경우에만 효과 후보로 분류한다. timeout만 줄고 RPS가 늘지 않으면 `SINK_STABILITY_ONLY`, 차이가 없으면 `SINK_NO_BENEFIT`, 성능·오류가 악화되면 `SINK_REGRESSION`으로 기록한다. 통계적 유의성이나 일반 운영 환경으로의 일반화는 주장하지 않는다.

## 실행 전 차단 조건

source/JAR/compose/fixture/actor/mock/pool/client timeout fingerprint 불일치, warm-up·collector·log capture 실패, application restart/OOM, DB integrity 실패, 종료 후 queue/active 미회수는 run을 invalid로 한다.

## 산출물

계획과 하네스만 이번 커밋에 포함한다. `backend/experiments/results/**` 및 `experiment/results/**` 원본은 생성하거나 커밋하지 않는다.
