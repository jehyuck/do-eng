# Experiment 1-13 결과 — Idle Connection Freshness Remediation

## Validity

- 최종 판정 대상: BASELINE 3회, REMEDIATION 3회, 총 6회
- 6개 core 모두 `measurementValidity=VALID`
- 모든 run에서 VU/initial VU 200, 1초 주기, AI 2,000ms, storage 100ms, 105초 측정, client timeout 10초, 30초 drain을 확인했다.
- 모든 run에서 unfinished request 0, 200명별 progress/picture/storage object 각 1건, drain 완료 및 최종 AI/storage backlog 0을 확인했다.
- source commit `900b5f95864cc19e257eeca27a6807df83c0291d`, application image `sha256:70d4c8033a301ad1e11f6cd8a46c7ef7710507fe8140bb10ce49f628b2b5be18`, mock image `sha256:3d00470cc138d56b8a42578b28c46c066bb31e10b489fc73a74cd019ebea1101`, fixture SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`가 6회에서 동일했다.
- 렌더링된 Compose는 `DOENG_EXTERNAL_MAX_IDLE_TIME_MS=0/4000` 외에 동일했다.
- pool collector failure는 6회 모두 0이었다.

`BASELINE-001`은 core, drain, 정합성 및 원시 수집이 모두 끝난 뒤 이미 종료된 pool collector PID에 `Wait-Process`를 호출한 후처리 오류가 발생했다. 부하는 재실행하지 않았다. 남아 있던 원본 pool JSONL, pcap, application log, DB/container raw를 검증한 뒤 동일 Run ID의 파생 집계와 provenance만 복구했다. 오류는 measurement나 observer 동작이 아니라 완료된 collector의 종료 상태를 확인하는 러너 분기였으므로 해당 core는 VALID로 유지했다. 복구 사실은 run provenance에 기록했다.

## Keep-alive provenance

- mock base image: `node:20-alpine`
- 실제 Node: `v20.20.2`
- `server.js`의 `server.keepAliveTimeout`, `server.timeout`, `server.maxRequestsPerSocket` override: 없음
- 런타임 기본 `keepAliveTimeout`: 5,000ms
- 실제 HTTP/1.1 응답: `Connection: keep-alive`, `Keep-Alive: timeout=5`
- BASELINE client max idle: 0(미설정)
- REMEDIATION client max idle: 4,000ms

Reactor Netty 1.0.28 API는 `maxIdleTime`을 pool에서 idle 상태인 channel을 닫기 위한 시간으로 정의한다. 이는 active request의 2초 AI 응답을 끊는 response timeout이 아니다. 공식 API: <https://projectreactor.io/docs/netty/1.0.28/api/reactor/netty/resources/ConnectionProvider.ConnectionPoolSpec.html#maxIdleTime(java.time.Duration)>

## Source and config diff

`ExternalServiceProperties`에 기본값 0인 `maxIdleTimeMs`를 추가했고, 음수를 거부했다. `ExternalHttpClientConfig`는 값이 양수일 때만 `ConnectionProvider.Builder.maxIdleTime(...)`을 호출한다. 따라서 0일 때 기존 provider 생성 의미를 유지한다.

Core에서 허용한 유일한 차이:

| 조건 | `DOENG_EXTERNAL_MAX_IDLE_TIME_MS` |
|---|---:|
| BASELINE | 0 |
| REMEDIATION | 4,000 |

## Deterministic tests

- Java 11 전체 테스트: 36 tests, failures 0, errors 0, skipped 0
- 500ms max idle + 800ms 대기: 두 번째 요청은 새 channel 사용
- max idle 0 + 800ms 대기: 기존 channel 재사용
- 500ms max idle + active 2초 응답: active request가 중단되지 않음
- 음수 설정 거부 및 기본값 0 확인
- Experiment 1-12 A~H positive control 재검증: 모두 통과

첫 positive-control 시도는 재사용 fixture가 로그에 고정한 `EXP112-CONTROL`과 새 러너가 합성 입력에 넣은 `EXP113-CONTROL`이 달라 correlation assertion이 실패했다. 이 결과는 보존했다. 합성 입력을 fixture의 기존 correlation contract에 맞춘 뒤 새 디렉터리에서 재검증했고, workload나 application 설정 변경 없이 통과했다.

## BASELINE results

| Run | AI PrematureClose | mock-close-before-acquire | HTTP 500 | timeout | connection error | HTTP 200 | accepted p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| BASELINE-001 | 64 | 64 | 161 | 1,688 | 7,474 | 4,736 | 9,180ms |
| BASELINE-002 | 4 | 2 | 15 | 1,710 | 13,181 | 1,729 | 9,931ms |
| BASELINE-003 | 10 | 9 | 45 | 2,028 | 14,572 | 2,153 | 9,332ms |

- AI PrematureClose 합계 78, run median 10
- mock-close-before-acquire 합계 75, 3/3 run에서 재현
- HTTP 200 median 2,153, accepted throughput median 20.50 RPS
- accepted p95 median 9,332ms
- uncontrolled failure median 14,906

## REMEDIATION results

| Run | AI PrematureClose | mock-close-before-acquire | HTTP 500 | timeout | connection error | HTTP 200 | accepted p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| REMEDIATION-001 | 56 | 56 | 64 | 1,524 | 5,036 | 5,495 | 8,735ms |
| REMEDIATION-002 | 67 | 67 | 99 | 831 | 1,252 | 6,919 | 8,498ms |
| REMEDIATION-003 | 45 | 43 | 45 | 948 | 2,475 | 6,450 | 8,632ms |

- AI PrematureClose 합계 168, run median 56
- mock-close-before-acquire 합계 166, 3/3 run에서 잔존
- HTTP 200 median 6,450, accepted throughput median 61.43 RPS
- accepted p95 median 8,632ms
- uncontrolled failure median 3,468

## Stale connection mechanism

BASELINE의 stale-reuse mechanism은 3/3에서 재현됐다. 그러나 REMEDIATION에서도 connection-level AI PrematureClose 168건이 모두 `REUSED_CHANNEL`이었고, 그중 166건은 mock FIN/RST가 해당 lease의 acquire보다 먼저 관측됐다. `REQUEST_PREPARED`는 있었지만 `REQUEST_SENT`는 없었다.

application connection event의 직전 `[released]`와 실패 lease의 `[acquired]` 사이를 계산한 실패 channel의 client-side idle age median은 REMEDIATION 각 run에서 3,652ms, 3,820ms, 3,407ms였다. 즉 실패의 상당수는 client가 기록한 idle age가 4초보다 짧은 상태에서도 발생했다. 이는 4초 설정이 이 시스템의 peer freshness 경계와 일치하지 않았다는 직접 관찰이다.

서버가 응답을 마친 뒤 keep-alive 시간을 세는 시점과 client가 응답 소비 후 connection을 pool에 release하여 idle 시간을 세는 시점이 같지 않을 수 있다는 설명은 가능하다. 다만 두 clock boundary를 request 단위로 직접 계측하지 않았으므로 원인으로 확정하지 않는다. 일부 실패는 계산된 idle age가 4초 이상이어서 lazy eviction/acquire 경쟁 또는 관측 timestamp 경계도 대안 설명으로 남는다.

## AI PrematureClose

- BASELINE: 78건 / AI stage start 대비 run별 1.027%, 0.125%, 0.248%
- REMEDIATION: 168건 / AI stage start 대비 run별 0.835%, 0.878%, 0.625%
- 합계 count 기준 감소율: `-115.38%`(감소가 아니라 115.38% 증가)
- 사전등록된 90% 이상 감소 조건: 실패

분모가 run마다 다르므로 count와 비율을 함께 보존했다. count와 비율 모두 remediation의 제거 효과를 지지하지 않는다.

## Reliability outcomes

| 지표 | BASELINE 값 / median | REMEDIATION 값 / median |
|---|---:|---:|
| HTTP 500 | 161, 15, 45 / 45 | 64, 99, 45 / 64 |
| client timeout | 1,688, 1,710, 2,028 / 1,710 | 1,524, 831, 948 / 948 |
| connection error | 7,474, 13,181, 14,572 / 13,181 | 5,036, 1,252, 2,475 / 2,475 |
| controlled 503 | 6,060, 459, 612 / 612 | 8,090, 11,451, 10,560 / 10,560 |
| 전체 uncontrolled failure | 9,323, 14,906, 16,645 / 14,906 | 6,624, 2,182, 3,468 / 3,468 |

새 uncontrolled failure category는 생기지 않았고 uncontrolled median guardrail은 통과했다. 그러나 이 결과는 run 간 host/처리량 변동과 admission 결과 구성이 크게 달라 단독 성능 개선 claim으로 사용하지 않는다.

## Performance guardrails

| 지표 | BASELINE median | REMEDIATION median | 판정 |
|---|---:|---:|---|
| HTTP 200 | 2,153 | 6,450 | 10% 초과 감소 없음 |
| accepted throughput | 20.50 RPS | 61.43 RPS | 감소 없음 |
| accepted p50 | 5,160ms | 4,687ms | 참고 |
| accepted p95 | 9,332ms | 8,632ms | 10% 초과 악화 없음 |
| accepted p99 | 9,893ms | 9,746ms | 참고 |
| app CPU sample median의 run median | 210.29% | 206.20% | 참고 |
| app max memory의 run median | 약 1.75GiB | 약 2.27GiB | 참고 |
| pool max active median | 226 | 282 | 참고 |
| pool max pending median | 7 | 7 | 참고 |
| drain time-to-zero median | 6,003ms | 4,009ms | 모두 30초 내 완료 |

성능 guardrail은 모두 통과했다. 하지만 primary mechanism을 제거하지 못했으므로 guardrail 통과만으로 remediation을 채택할 수 없다.

## Connection churn

| 조건 | Run | distinct/new channels | configured leases | reused leases |
|---|---|---:|---:|---:|
| BASELINE | 001 | 2,092 | 18,202 | 16,110 |
| BASELINE | 002 | 2,252 | 8,760 | 6,508 |
| BASELINE | 003 | 2,377 | 10,832 | 8,455 |
| REMEDIATION | 001 | 1,816 | 19,538 | 17,722 |
| REMEDIATION | 002 | 1,469 | 22,623 | 21,154 |
| REMEDIATION | 003 | 1,252 | 21,316 | 20,064 |

4초 설정이 과도한 new-connection churn을 만들었다는 증거는 없다. 오히려 distinct/new channel count는 remediation에서 낮았다. 이 역시 stale reuse 제거 실패와 함께 관찰된 outcome이며 별도 최적화 claim으로 확대하지 않는다.

## Final verdict

`NOT_EFFECTIVE`

사전등록 판정식 중 다음을 실패했다.

1. REMEDIATION 3회 모두 mock-close-before-acquire reused PrematureClose가 0이어야 하나 56, 67, 43건이었다.
2. AI PrematureClose 합계가 90% 이상 감소해야 하나 78건에서 168건으로 증가했다.
3. 동일 failure가 다른 이름으로만 이동한 경우가 아니라 원래 stale-reuse failure 자체가 계속 관찰됐다.

따라서 `DOENG_EXTERNAL_MAX_IDLE_TIME_MS=4000`은 채택하지 않으며 기본값 0을 유지한다. 설정 기능은 향후 명시적 판단을 위해 코드에 남길 수 있지만, 이번 결과를 근거로 production 기본값을 4초로 바꾸지 않는다.

## Claim boundary

확인된 주장:

- 이 고정된 Node 20 mock/로컬 Docker/VU200 workload에서 baseline stale pooled connection 재사용 현상은 3/3 재현됐다.
- client maxIdleTime 4초는 적용됐으나 stale reused AI PrematureClose를 제거하거나 90% 이상 줄이지 못했다.
- 따라서 4초 idle freshness는 이 workload의 reliability remediation으로 채택되지 않았다.

확인되지 않은 주장:

- Reactor Netty의 일반적 결함
- 모든 server/client 조합에서 maxIdleTime이 무효라는 결론
- 4초 외 다른 값, background eviction, LIFO, maxLifeTime의 효과
- remediation이 처리량을 일반적으로 3배 향상한다는 결론
- server clock과 client idle clock의 정확한 차이가 단독 원인이라는 결론

## Experiment 1-9~1-12 영향

- Experiment 1-9의 admission/overload control 결론은 유지된다. 이번 결과는 accepted request 내부 transport lifecycle의 별도 문제다.
- Experiment 1-10~1-12에서 관찰한 AI PrematureClose 및 mock 선종료 pooled connection 재사용 메커니즘은 baseline 3/3 재현으로 강화됐다.
- Experiment 1-12가 제안한 단일 후보 중 4초 maxIdleTime은 이번 고정 조건에서 기각됐다.
- 이 기각은 이전 attribution을 뒤집지 않는다. 원인 후보에 대한 특정 remediation이 효과적이지 않았다는 결과다.

## Remaining limitations

- request ID와 실패 channel lease의 1:1 binding은 outbound write 이전 실패 때문에 여전히 완전하지 않다.
- server response-finished 시각과 client pool release 시각의 차이를 동일 request/connection에서 직접 집계하지 않았다.
- run 간 처리량과 admission/connection-error 구성이 크게 달라 secondary 성능 수치는 변동성이 크다.
- local Docker와 Node mock 결과를 실제 AI/S3 운영 환경으로 일반화할 수 없다.
- hard stop에 따라 4초 외 값과 다른 pool 정책은 실행하지 않았다.

주요 집계 artifact:

- `experiment/summaries/experiment-1-13-paired-summary.json`
- `experiment/summaries/experiment-1-13-condition-summary.json`
- `experiment/summaries/experiment-1-13-config-diff.json`
- `experiment/summaries/experiment-1-13-keepalive-provenance.json`
- `experiment/summaries/experiment-1-13-verdict.json`
