# Experiment 1-8 외부 의존성별 Connection Pool 분리 설계

## 1. 문제

현재 WebFlux REST 경로의 TOKEN, AI, STORAGE outbound HTTP 호출은
`ConnectionProvider("doeng-external")` 하나를 공유한다. 기존 VU200 진단에서
active connection은 400 부근에 머무는 동안 pending acquire가 크게 늘고,
`PoolAcquirePendingLimitException`과 HTTP 500이 관찰됐다. 단계별 실패는
TOKEN·AI·STORAGE에 집중됐고 DB가 같은 형태로 포화된 근거는 부족했다.

이번 실험의 질문은 하나다.

> 동일한 총 active connection·pending queue 예산과 동일 workload에서
> TOKEN·AI·STORAGE의 `ConnectionProvider`를 분리하면 shared pool의 pending
> overflow와 uncontrolled HTTP500을 제거하면서 성공 처리량과 tail latency를
> 회복할 수 있는가?

## 2. Source topology

기준 source commit은 `fadd387`이며 기준 branch는
`experiment/doeng-pending-acquire-diagnostic`이다.

기존 구조:

```text
ConnectionProvider("doeng-external")
        -> HttpClient
        -> externalWebClientBuilder
             -> TokenComponent
             -> AiGameController
             -> HttpMissionImageStorage
```

수정 구조는 startup에서 재사용되는 세 WebClient와 네 provider bean을 둔다.
SHARED에서는 세 WebClient가 `sharedConnectionProvider`를 사용하고,
ISOLATED에서는 각각 `tokenConnectionProvider`, `aiConnectionProvider`,
`storageConnectionProvider`를 사용한다. Reactor Netty event-loop resource는
분리하지 않는다.

## 3. Runtime evidence

Experiment 1-6 및 Experiment 1-7 raw에서 AI 지연이 증가하거나 pool pending이
증가한 조건에서 accepted tail과 일부 stage duration이 악화됐다. 그러나
pending Gauge만으로는 acquire wait 시간과 HTTP500의 인과를 확정할 수 없어
Experiment 1-7은 분류 B로 종료됐다. 따라서 이번 실험은 pool 크기를 늘리는
대신 같은 총예산에서 provider 간 contention을 제거하는 remediation 가설을
검증한다.

## 4. 변경 가설

공유 provider에서는 TOKEN·AI·STORAGE가 같은 acquire queue를 사용하므로 한
단계의 burst가 다른 단계의 connection acquire를 지연·거부할 수 있다.
provider topology를 분리하면 각 외부 의존성이 자신의 budget 안에서 대기하고,
한 의존성의 burst가 다른 의존성의 queue를 직접 소진하지 않을 것이다.
이 가설이 맞다면 ISOLATED에서 HTTP500과
`PoolAcquirePendingLimitException`이 반복적으로 제거되고 accepted p95와
successful RPS가 회복된다.

## 5. SHARED / ISOLATED 구조

### SHARED

```text
doeng-external
  maxConnections = 400
  pendingAcquireMaxCount = 800

TOKEN / AI / STORAGE -> doeng-external
```

### ISOLATED

```text
doeng-token
  maxConnections = 40
  pendingAcquireMaxCount = 80

doeng-ai
  maxConnections = 320
  pendingAcquireMaxCount = 640

doeng-storage
  maxConnections = 40
  pendingAcquireMaxCount = 80
```

## 6. Active budget 동일성

SHARED active budget은 400이다. ISOLATED의 합은
`40 + 320 + 40 = 400`으로 동일하다. 각 provider의 실제 active max와
동일 timestamp의 provider active 합을 별도로 기록한다. provider별 max를
단순히 더해 동일 timestamp max라고 해석하지 않는다.

## 7. Pending budget 동일성

SHARED pending budget은 800이다. ISOLATED의 합은
`80 + 640 + 80 = 800`으로 동일하다. collector는 provider별 pending과
동일 timestamp pending 합의 max를 계산하며, pending budget을 초과하거나
계약과 다른 설정이면 해당 run을 invalid 처리한다.

## 8. Admission OFF 이유

두 arm 모두 `DOENG_AI_ADMISSION_ENABLED=false`로 고정한다. FULL_PATH
admission 320을 사용하면 요청이 pool에 도달하기 전에 320으로 제한되어
shared pool failure가 가려질 수 있다. 이번 질문은 503 선차단이 아니라
shared pool topology의 application-side remediation 효과이므로 admission을
양쪽에서 동일하게 끈다. HTTP500을 HTTP503으로 바꾸는 예외 mapping은
추가하지 않는다.

## 9. 독립변수

유일한 독립변수는 다음 환경변수다.

```text
DOENG_EXTERNAL_POOL_MODE = SHARED | ISOLATED
```

ISOLATED에서 각 budget과 SHARED 총예산이 다르면 startup validation error로
중단한다. 알 수 없는 enum 값은 조용히 fallback하지 않는다.

## 10. 동결 변수

- WebFlux REST `/game/face`
- VU 200, measurement 105s, pacing 1s
- AI delay 2,000ms, storage delay 100ms, client timeout 10s
- application 2 CPU / 3 GiB, DB pool 10
- same fixture, payload, auth/token, mock behavior, DB/storage completion
- fresh JVM per run
- JFR OFF, comprehensive snapshot OFF
- DB/container/stage/pool observer ON
- load-stop snapshot ON, 30s drain ON
- admission OFF
- connect/response/pending timeout과 codec 설정

## 11. 실행 순서

먼저 `RUN-20260802-EXP18-ISOLATED-SCOUT-001`을 실행해 provider meter,
budget, admission OFF, collector 분리를 확인한다. Scout는 최종 aggregate에
포함하지 않는다.

Scout가 통과하면 다음 crossover 순서로 core를 실행한다.

```text
RUN-20260802-EXP18-SHARED-001
RUN-20260802-EXP18-ISOLATED-001
RUN-20260802-EXP18-ISOLATED-002
RUN-20260802-EXP18-SHARED-002
RUN-20260802-EXP18-SHARED-003
RUN-20260802-EXP18-ISOLATED-003
```

각 run 전 application container를 recreate하고, mock reset·DB/storage
fixture·pre-run idle·provenance를 확인한다. 성능이 나쁘다는 이유로 run을
invalid 처리하지 않는다. collector/configuration/setup failure에 한해
arm별 최대 한 번의 replacement를 허용한다.

## 12. 성공 기준

세부 판정은 다음을 모두 만족할 때 A로 분류한다.

- SHARED 3 VALID, ISOLATED 3 VALID
- provider별 metric coverage와 configuration provenance PASS
- ISOLATED 3회 모두 HTTP500 = 0,
  `PoolAcquirePendingLimitException` = 0, connection error = 0
- ISOLATED successful RPS median >= 100
- ISOLATED successful RPS median >= SHARED median × 1.50
- ISOLATED accepted p95 median <= 5,000ms이며 SHARED보다 낮음
- provider active max와 동일 timestamp active 합이 budget 이내
- pending configured total = 800
- DB/storage correctness 및 drain PASS

## 13. 실패 기준

HTTP500·pool exception이 제거됐지만 처리량 또는 p95 기준을 충족하지 못하면
B(`RESILIENCE IMPROVED, CAPACITY NOT RECOVERED`)로 분류한다.

HTTP500이나 pool exception이 지속되거나, successful RPS가 개선되지 않거나,
p95가 악화되거나, 특정 isolated pool에서 overflow가 발생하면
C(`POOL ISOLATION NOT EFFECTIVE`)로 분류한다.

provider wiring·총 budget·admission·collector·workload 계약이 틀리거나
VALID cohort를 확보하지 못하면 F(`INVALID`)로 분류한다.

## 14. Claim boundary

A가 되더라도 결론은 이 workload와 이 총 connection budget에서 provider
분리가 failure containment·처리량·tail latency를 개선했다는 범위로
제한한다. WebFlux 일반 우위, 모든 pool allocation의 최적성, 실제 AI/S3
서비스의 보편적 결과를 주장하지 않는다.

## 15. Hard stop

A이면 추가 tuning을 자동 실행하지 않고
`Isolated WebFlux vs MVC400 symmetric comparison`을 다음 후보로만 기록한다.
B 또는 C이면 budget 재배분, pending sweep, timeout·AI delay·VU 변경,
admission 재활성화, MVC 비교 및 추가 remediation을 자동 실행하지 않는다.
F이면 raw와 invalid 사유를 보존하고 동일 arm replacement 범위만 적용한다.
