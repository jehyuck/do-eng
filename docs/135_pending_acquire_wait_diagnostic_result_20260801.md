# Connection Pending-Acquire Wait 진단 결과

## 확인한 Source

- branch: `experiment/doeng-pending-acquire-diagnostic`
- source commit: `cb95af2` (`관측: connection acquire 대기 Timer 수집 추가`)
- Reactor Netty runtime: `reactor-netty-core 1.0.28`
- 대상 provider: `doeng-external`
- 기존 `DiagnosticPoolEndpoint`는 pool Gauge만 읽고
  `reactor.netty.connection.provider.pending.connections.time`을 Gauge처럼
  취급하고 있었다.
- 이번 수정은 Micrometer `Timer` API로 해당 meter를 읽어
  `count`, `totalTimeMs`, `meanMs`, `maxMs`, percentile snapshot 및 tags를
  보존하도록 한 observation-only 변경이다.

## 계측 오류

기존 endpoint에는 pending-acquire wait Timer를 읽는 경로가 없었다. 따라서
기존 raw에서는 active/pending connection Gauge만 확인할 수 있었고 실제
connection acquire 대기시간은 `NOT AVAILABLE`이었다. 이번 pair에서도
runtime registry에 해당 Timer meter가 등록되지 않아 Timer row가 생성되지
않았다. 이는 대기시간이 0이라는 뜻이 아니다.

## 수정한 계측

- `DiagnosticPoolEndpoint`에서 Gauge와 Timer를 분리해 읽도록 수정했다.
- Timer가 존재할 때만 count/total/mean/max/percentile을 JSON으로 반환한다.
- Timer 또는 percentile이 runtime에서 제공되지 않으면 추정값을 만들지 않고
  빈 결과로 보존한다.
- `DiagnosticPoolEndpointTest`에서 Timer 2회 기록(count 2, total 40ms,
  mean 20ms, max 28ms)과 tags 반환을 검증했다.
- pool collector는 기존처럼 endpoint의 `metrics` 배열을 그대로 JSONL에
  보존하므로 별도 continuous snapshot이나 JFR을 추가하지 않았다.

## Build와 Test

- Docker JDK 11 / Gradle offline `gradle test`: `BUILD SUCCESSFUL`
- diagnostic image build: `doeng-flux-exp17-pending-diagnostic-20260801:latest`
- compose configuration validation: 통과
- source/config/resource/pool/workload 변경: 없음
- JFR: OFF
- comprehensive application snapshot: OFF

## Diagnostic Runs

| Run | AI delay | Measurement validity | 성공 | controlled 503 | HTTP 500 | client timeout | accepted p95/p99 (ms) | drain |
|---|---:|---|---:|---:|---:|---:|---:|---|
| `RUN-20260801-EXP17-AI1000-DIAG-001` | 1,000ms | VALID | 13,222 | 7,199 | 5 | 200 | 3,950 / 8,008 | 2,007ms, completed |
| `RUN-20260801-EXP17-AI500-DIAG-001` | 500ms | VALID | 12,069 | 8,296 | 0 | 51 | 6,224 / 8,944 | 2,000ms, completed |

두 run 모두 corrected accounting, pre-run idle gate, load-stop snapshot,
30초 drain, DB/storage consistency, DB/container collector 및 provenance
검증을 통과했다. 성능 결과(503, timeout, tail latency, backlog)는
Measurement Validity와 별개의 System Outcome으로 보존했다.

## 기존 지표 비교

| 항목 | AI1000 | AI500 | 관찰 |
|---|---:|---:|---|
| throughput (requests/s) | 196.44 | 195.70 | 거의 동일 |
| max client in-flight | 698 | 765 | AI500가 높음 |
| pool active max | 321 | 320 | pool 상한 400에 도달하지 않음 |
| pool pending max | 19 | 42 | AI500에서 증가 |
| pool total max | 328 | 322 | 유사 |
| TOKEN interval mean | 357.63ms | 554.97ms | AI500 증가 |
| AI interval mean | 1,448.68ms | 1,192.16ms | AI500가 낮지만 synthetic delay만으로 설명 불가 |
| STORAGE interval mean | 509.59ms | 768.44ms | AI500 증가 |
| DB interval mean | 81.50ms | 109.24ms | AI500 증가 |
| stage maxInFlight (TOKEN/AI/STORAGE/DB) | 173/287/212/111 | 154/210/210/141 | stage별 방향이 일관되지 않음 |
| application container CPU 평균/최대 | 199.11% / 215.32% | 202.21% / 221.25% | 유사 |
| DB Threads_running 최대 | 1 | 2 | 낮은 수준 |
| load-stop AI/storage in-flight | 81 / 162 | 148 / 42 | drain 전 backlog 양상이 다름 |

Application continuous snapshot은 계약상 OFF였으므로 event-loop pending,
JVM thread/memory 및 애플리케이션 내부 queue의 시계열은 이번 raw에서
직접 비교할 수 없다. container CPU/PIDs와 DB collector 결과만 관찰했다.

## Pending-Acquire Timer 비교

| metric | AI1000 | AI500 | 판정 |
|---|---|---|---|
| `reactor.netty.connection.provider.pending.connections.time` row count | 0 | 0 | `NOT AVAILABLE` |
| count | NOT AVAILABLE | NOT AVAILABLE | runtime Timer meter 미노출 |
| totalTimeMs | NOT AVAILABLE | NOT AVAILABLE | 추정하지 않음 |
| meanMs | NOT AVAILABLE | NOT AVAILABLE | 추정하지 않음 |
| maxMs | NOT AVAILABLE | NOT AVAILABLE | 추정하지 않음 |
| p50 / p95 / p99 | NOT AVAILABLE | NOT AVAILABLE | percentile snapshot 미수집 |

Pool pending Gauge 자체는 AI500에서 19→42로 증가했지만, 이것만으로
connection acquire 대기시간의 크기·tail 또는 accepted p95 악화의 인과를
확정할 수 없다.

## Measurement Validity

- `RUN-20260801-EXP17-AI1000-DIAG-001`: `VALID`
- `RUN-20260801-EXP17-AI500-DIAG-001`: `VALID`
- raw pool/stage/admission/client/DB/container/mock/drain/provenance artifact:
  모두 보존
- collector exit code: 0
- JFR 및 comprehensive snapshot: 비활성
- Timer 부재는 측정된 성능 결과를 invalid로 만드는 사유가 아니라, 이
  diagnostic 질문의 계측 공백으로 기록한다.

## 결과 분류

**B — Timer가 runtime에서 측정되지 않아 connection pending-acquire wait를
확정할 수 없음**

AI500에서 pool pending Gauge와 TOKEN/STORAGE/DB stage 평균 및 accepted tail이
악화된 관찰은 있었지만, Timer의 count/mean/p95/p99가 양 arm 모두
`NOT AVAILABLE`이다. 따라서 A(수정 가능한 connection wait 병목 확인)로
올릴 직접 근거가 없다. 두 run은 유효하므로 F(진단 pair 무효)도 아니다.

## 증명된 내용

- Timer를 읽어 보존하는 source/test 경로는 구현 및 build/test로 확인했다.
- 동일 계약의 AI1000/AI500 diagnostic pair는 모두 VALID로 실행·보존됐다.
- AI500에서 pool pending Gauge 최대치와 일부 stage 평균, accepted tail이
  증가했지만 처리량은 거의 동일했다.
- 두 run 모두 load-stop backlog는 30초 drain 안에 0으로 해소됐다.

## 증명하지 못한 내용

- Reactor Netty connection acquire 대기시간의 평균 또는 tail
- accepted p95 악화의 단일 원인이 connection-pool 대기라는 인과관계
- permit holding, scheduler queue, request body/Base64 decode,
  response composition 시간
- event-loop pending과 connection wait의 시간적 선후
- application remediation이 성능을 개선한다는 사실

## 허용 가능한 다음 작업

이번 결과만으로는 추가 core cohort, 튜닝, remediation을 진행하지 않는다.
추가 diagnostic이 별도로 승인되는 경우에만 Timer가 실제 runtime meter로
등록되는지 확인하는 최소 계측 검토를 할 수 있다.

## 금지된 다음 작업

- permit/pool/VU/timeout/resource 변경
- AI delay 250ms 또는 추가 latency 실험
- MVC 비교 또는 full core cohort 재실행
- Timer가 없다는 이유로 값을 0 또는 추정치로 대체
- 이번 pair만으로 connection-pool 병목이나 remediation을 확정
- 기존 Experiment 1-6 분류 및 raw 삭제/변경
