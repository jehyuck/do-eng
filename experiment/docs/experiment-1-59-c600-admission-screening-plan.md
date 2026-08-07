# Exp159 C600 Admission Gate Capacity Screening Plan

## 질문

Exp158에서 고정한 provider 구성(TOKEN/AI/STORAGE=100/600/100, ISOLATED, Sink OFF)에서 whole-request Admission Gate 한도가 400·600·800일 때 시간당 accepted HTTP 200 완료량과 backlog/timeout이 어떻게 달라지는지 확인한다.

## 기준선과 재사용

Exp158의 `C600-100-R1`은 동일 source/image, provider·workload·timeout·resource·fixture 조건의 Admission OFF 교정 run으로 재사용한다. 최초 `C600-100`은 잘못 렌더링된 invalid run이므로 제외한다. 새 OFF run은 실행하지 않는다.

## Admission 구현 사실

`AiOutboundAdmissionGate.execute`는 `Mono.defer` 안에서 `AdmissionProperties.resolvedMode()`를 읽고, ENFORCE에서는 `tryAcquireEnforce`로 CAS 기반 permit을 획득한다. 거절 시 `AiCapacityExceededException`을 반환하고, 획득한 permit은 downstream publisher의 `doFinally`에서 성공·오류·취소 모두 release된다. `GameFaceService`의 request path 경계에서 whole-path 모드로 적용된다. Admission 503과 downstream HTTP 500을 분리해 기록한다.

## 고정 조건

- VU/active missions 200, staggered, 1초 간격, 30초
- client timeout 15초, pending acquire timeout 10초, drain 15초
- AI 2초, storage 100ms, app 2CPU/3GiB, JVM Xms512m/Xmx2g/G1GC, DB pool 10
- provider: TOKEN 100/160, AI 600/960, STORAGE 100/160, ISOLATED
- Sink OFF, 동일 fixture/source/image/mock/auth 계약

## 실행 순서

`G600 → G400 → G800`, 각 한 번, fresh recreate. 명확한 winner와 부작용이 모두 확인될 때만 confirmation 한 번을 별도 승인한다.

## 관측

accepted HTTP200/sec를 primary로 하고 Admission 503, uncontrolled 500, timeout, connection error, HTTP200 latency, provider active/pending, gate acquired/rejected/released/active, stage in-flight, CPU/memory, load-stop backlog와 drain을 함께 보존한다. 수집되지 않은 값은 `NOT_AVAILABLE`로 둔다.

## 판정

Gate가 accepted completion을 반복적으로 높이고 uncontrolled failure·tail latency·OOM/restart·permit leak을 악화시키지 않으면 `ADMISSION_SIGNAL=SUPPORTED`로 기록할 수 있다. 명확한 envelope가 없으면 `INCONCLUSIVE`이며 추가 grid search는 하지 않는다. Gate 600을 최적값 또는 일반 운영값으로 주장하지 않는다.
