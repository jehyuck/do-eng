# Experiment 1-10 End-to-End Transport Failure Attribution 결과

## 실행 범위

Experiment 1-9 ENFORCE-001의 transport/HTTP 500 경계를 확인하기 위해 동일 조건으로 CLEAN 3회와 REUSED 3회를 수행했다. admission 320, shared pool 400/800, VU200, AI 2초, storage 100ms, frame/reconnect 1초, duration 105초, client timeout 10초, app 2 CPU/3 GiB, DB pool 10을 유지했다. JFR과 comprehensive application snapshot, continuous mock polling은 껐고 DB/container monitor, load-stop snapshot, 30초 drain은 유지했다.

## validity

| Run | Measurement validity | 성공 | HTTP 500 | client timeout | admission 503 | accepted p95/p99 (ms) | drain |
|---|---|---:|---:|---:|---:|---:|---|
| CLEAN-ENFORCE-001 | VALID | 12,459 | 0 | 0 | 8,226 | 2,934 / 5,431 | 3,011 ms |
| CLEAN-ENFORCE-002 | VALID | 12,468 | 0 | 0 | 8,204 | 3,063 / 5,170 | 3,001 ms |
| CLEAN-ENFORCE-003 | VALID | 10,447 | 12 | 6 | 10,208 | 4,555 / 6,661 | 3,012 ms |
| REUSED-ENFORCE-001 | VALID | 12,071 | 0 | 1 | 8,577 | 2,731 / 5,847 | 3,013 ms |
| REUSED-ENFORCE-002 | VALID | 12,541 | 0 | 0 | 8,146 | 2,863 / 6,096 | 3,001 ms |
| REUSED-ENFORCE-003 | VALID | 9,267 | 360 | 269 | 10,748 | 4,285 / 8,019 | 3,012 ms |

모든 core run은 pre-run idle, raw artifact, DB/container collector, load-stop/drain, consistency gate를 통과했다. 높은 error, p95, backlog는 validity 실패로 처리하지 않았다.

## failure boundary

현재 결과의 최종 분류는 **F — UNRESOLVED**다.

- CLEAN-001/002와 REUSED-001/002에서는 uncontrolled HTTP 500이 재현되지 않았다.
- CLEAN-003과 REUSED-003에서는 각각 HTTP 500/timeout이 재현됐다. clean에서 재현되지 않고 reused에서만 재현되는 패턴이 아니다.
- 재현 run에서는 애플리케이션 inbound filter가 해당 request ID를 수신했고 `signal=onError`, `status=500`을 남겼다.
- 동시에 AI stage에서 `PrematureCloseException (Connection prematurely closed BEFORE response)`가 관찰됐다. CLEAN-003은 24건, REUSED-003은 694건의 해당 event가 있었다. REUSED-003에는 `REQUEST_SEND_ERROR` 13건과 `UNKNOWN_OUTBOUND` 5건도 있었다.
- 그러나 Reactor Netty의 error callback이 `request=null`인 경우가 있어 premature-close event의 request ID가 보존되지 않았다. 따라서 HTTP 500 request ID와 outbound exception을 일대일로 증명할 수 없다.

## confirmed exception/cause

확인된 예외 클래스는 `reactor.netty.http.client.PrematureCloseException`이며 stage는 AI다. 이는 WebClient outbound에서 응답 전 연결이 닫힌 관찰 사실을 의미한다.

다만 다음은 확인되지 않았다.

- 해당 예외가 각 HTTP 500의 직접 원인이라는 request-level 인과
- load driver의 connection error가 원인이었는지 여부
- mock 서버가 먼저 연결을 닫았는지 여부
- event-loop 포화가 선행 원인이었는지 여부

Node 결과에서는 transport category가 대부분 `NONE`이고, deadline timeout만 CLEAN-003 6건, REUSED-001 1건, REUSED-003 269건이었다. `ECONNRESET`·`ECONNREFUSED` 등 Node cause chain 기반의 확정적 load-driver transport category는 관찰되지 않았다.

## request ID correlation

inbound request ID는 기록됐다. run당 약 41천 건의 `DOENG_INBOUND_EVENT`가 저장됐고, 정상 요청에서는 TOKEN/AI/STORAGE callback이 request ID와 missionRunId를 함께 남겼다.

그러나 실패 callback 일부는 `requestId=null`, `remoteAddress=null`로 기록됐다. 특히 `PrematureCloseException` event가 이 형태였다. 따라서 현재 correlation은 run/stage/time-window 수준이며, 실패 request 한 건의 inbound → AI callback → client result를 완전하게 연결하지 못한다.

## clean/reused difference

clean과 reused 모두 2회는 안정적이고 1회는 degraded였다.

- clean: 2회 안정, CLEAN-003 degraded
- reused: 2회 안정, REUSED-003 degraded
- mock resetGeneration은 run별 warm-up reset을 반영했고, clean/reused의 degraded 여부와 단순히 일치하지 않았다.
- 모든 run에서 drain은 완료됐고 종료 후 AI/storage in-flight는 0이었다.

따라서 현재 6회 결과는 dependency state reuse만으로 실패를 설명하지 못하며, 반복 변동성이 존재함을 보여준다.

## impact on Experiment 1-9 claim

Experiment 1-9의 “ENFORCE 320이 overload를 명시적 503으로 보호한다”는 관찰은 이번 run에서도 대부분 유지됐다. 그러나 6회 중 CLEAN-003과 REUSED-003에서 uncontrolled HTTP 500/timeout이 다시 관찰됐으므로, ENFORCE 320이 모든 transport/application failure를 제거한다고 확대할 수 없다.

이번 결과로 추가되는 제한은 다음과 같다.

> ENFORCE 320은 일반 run에서 overload 결과를 admission 503으로 분리하는 보호 경계를 제공했지만, 반복 실행의 일부 run에서 AI outbound premature close와 HTTP 500이 남았다. 그 직접 인과와 재현 경계는 현재 correlation 계측만으로 확정할 수 없다.

## required remediation

성능 튜닝이나 pool/admission 변경은 권고하지 않는다. 진단을 계속할 필요가 있다면 단 하나의 우선 과제는 다음이다.

`Reactor Netty error callback에서 request ID와 connection identity를 보존하여 실패 request와 outbound exception을 일대일로 연결하는 관측 보강`

이는 execution semantics를 바꾸지 않는 계측 보강이며, 현재 결과의 F 분류를 해소하기 위한 최소 조건이다. 본 작업에서는 구현·추가 부하 실행을 수행하지 않았다.

## no remediation

- admission limit 320 변경 금지
- shared pool/pending/timeout/retry 변경 금지
- scheduler, Base64, DB pool, mock latency, resource 변경 금지
- MVC 비교 또는 추가 VU sweep 금지
- 결과가 좋아질 때까지 반복 금지

## 보존 artifact

각 run의 `experiment/results/<RUN-ID>/`에 client raw/summary, application.log, application-metrics, container, database, mock, drain, verification, run-config를 보존했다. CLEAN-ENFORCE-001은 최초 log capture 과정에서 `application-test.log`에 보존된 원본을 `application.log`로 복구했으며, 원본 파일도 함께 남겼다.

## 최종 판정

**F — UNRESOLVED**

현재 evidence는 AI WebClient의 premature close가 재현 run과 함께 나타났다는 사실은 보여주지만, request-level correlation이 끊겨 있어 load driver, WebFlux inbound/event loop, outbound AI, mock dependency 중 하나를 수정 가능한 단일 병목으로 확정하지 못한다.
