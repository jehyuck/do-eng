# Experiment 1-11 AI Premature Close Correlation 결과

## 작업 상태

`완료`

- 결정적 correlation test A~F 통과
- CLEAN core 3회 완료
- 세 core 이후 추가 부하 실행 중단
- 원시 로그와 request ID join artifact 보존

## 고정 구현과 실행 계약

- 구현 source commit: `1b7c61f29658ab5e0a55cbdb2066ac720077ff24`
- join run-scope 보정 commit: `4299a80711a8817c87db2e1b9f6e9fcaed6efe4b`
- client-abort 순서 보정 commit: `0492f88ee1ac2df7f717e8a6d38f6687253d5a68`
- application image: `doeng-flux-exp111-correlation-20260802:latest`
- application image ID: `sha256:cf406da8fc763de2f9eac0f6bb0d8485c7f8c5f4f0e2418dce40dab9e428764d`
- Compose hash: `dfff8c07c1b5cb2ef9839de37f9589c242d2c72cf3c32505c4b6b9c777ac279d`
- VU 200, initial VU 200, frame/reconnect 1초
- AI 2초, storage 100ms, duration 105초, client timeout 10초, drain 30초
- app 2 CPU/3 GiB, shared outbound pool 400/pending 800, DB pool 10
- full-path admission ENFORCE 320

`4299a80`과 `0492f88`은 application, mock, 부하, 관측 event를 변경하지 않은 파생 join 보정이다. 첫 core 실행 source는 `1b7c61f`, 나머지 두 core의 HEAD는 `4299a80`이지만 세 실행의 application image와 Compose hash는 동일하다.

## 사전 결정적 검증

| 검증 | 결과 |
|---|---|
| A. inbound header → Reactor Context → AI header | PASS |
| B. admission 503이면 AI stage/mock 미호출 | PASS |
| C. 정상 AI 응답이 mock response finish와 HTTP 200으로 연결 | PASS |
| D. 강제 response 전 close가 동일 ID의 mock incomplete → AI PrematureClose → HTTP 500으로 연결 | PASS |
| E. client cancellation 이후 mock incomplete close 발생 | PASS |
| F. diagnostic OFF publisher/error/503 의미 유지 | PASS |

Java 11 clean test와 deterministic E2E를 모두 통과한 뒤에만 core를 실행했다. Test D는 진단 경로의 positive control이며 실제 core 원인을 미리 단정하는 근거로 사용하지 않는다.

## Core 결과

| Run | Validity | 성공 | controlled 503 | uncontrolled | accepted p95 | HTTP 500 | timeout | AI PrematureClose | complete join | incomplete join |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `CLEAN-002` | VALID | 12,229 | 8,461 | 0 | 4,523ms | 0 | 0 | 0 | 20,690 | 0 |
| `CLEAN-003` | VALID | 12,139 | 8,385 | 142 | 4,234ms | 74 | 68 | 58 | 20,592 | 74 |
| `CLEAN-004` | VALID | 6,773 | 12,636 | 843 | 6,910ms | 377 | 466 | 208 | 19,886 | 366 |

세 run 모두 pre-run idle, warm-up, collector, drain, DB/storage consistency gate를 통과했다. 성능 outcome이 나쁜 것은 INVALID 사유로 사용하지 않았다.

## Request ID join 판정

### AI PrematureClose 266건

- `CLEAN-003` 58건, `CLEAN-004` 208건이다.
- 266건 모두 동일 request ID에서 inbound 수신, AI stage 시작, AI `STAGE_FAILED`, 최종 HTTP 500을 연결할 수 있었다.
- 266건 모두 mock의 `MOCK_AI_REQUEST_RECEIVED`가 없어 completeness는 `MISSING_MOCK`이었다.
- 따라서 실제 core의 AI PrematureClose를 `mock이 해당 HTTP 요청을 받은 뒤 응답 도중 닫았다`고 판정할 수 없다.
- 반대로 AI 요청이 mock HTTP request lifecycle에 진입하기 전의 outbound transport/connection 경계에서 끊겼다는 판정은 현재 evidence가 지지한다.

### Client timeout과 mock incomplete 32건

- `CLEAN-004`에서 mock incomplete response 32건이 있었다.
- 32건 모두 client deadline abort가 mock incomplete close보다 먼저였다.
- 이 32건은 AI PrematureClose 208건과 겹치지 않는다.
- 따라서 client cancellation은 별도의 timeout 결과를 설명하지만, 관측된 AI PrematureClose의 선행 원인으로 지지되지 않는다.

### Shared outbound transport 징후

- `CLEAN-003`에서는 TOKEN 16건과 AI 58건에서 PrematureClose가 기록됐다.
- `CLEAN-004`에서는 TOKEN 148건, AI 208건, STORAGE 9건에서 PrematureClose가 기록됐다.
- 같은 실행에서 mock connection-level `ECONNRESET`은 각각 6건과 113건이었다.
- 여러 stage가 동일 shared outbound provider를 사용한다는 점과 방향은 일치한다.
- 다만 connection event에는 request ID가 없고 event 수가 request failure 수와 일치하지 않으므로 특정 request와 특정 socket reset의 인과를 직접 연결하지 않는다.

## 최종 판정

`PARTIALLY ATTRIBUTED — failure boundary confirmed, initiating actor not confirmed`

현재 evidence로 확인된 내용:

1. 실제 HTTP 500 일부는 AI stage의 `PrematureCloseException`에서 발생했다.
2. 그 요청은 mock AI HTTP handler에 도달한 request-level evidence가 없다.
3. mock이 요청을 받은 뒤 응답을 덜 쓰고 닫은 경우와 client deadline이 먼저 발생한 경우는 별도 chain으로 구분된다.
4. 따라서 실제 AI PrematureClose의 경계는 `application outbound connection → mock HTTP request 수신 전`으로 좁혀진다.

현재 evidence로 확인되지 않은 내용:

- 어느 peer가 해당 TCP connection을 먼저 닫았는지
- Reactor Netty가 stale/closed pooled connection을 재사용했는지
- 특정 mock socket `ECONNRESET`이 특정 AI request의 PrematureClose를 직접 발생시켰는지
- 단일 수정 가능한 코드 지점

결론적으로 `mock AI가 응답 도중 임의로 끊어서 발생했다` 또는 `client timeout이 먼저라서 발생했다`는 설명은 core evidence와 일치하지 않는다. shared outbound connection 계층은 가장 가까운 후보 경계지만, 정확한 initiating actor까지 확정되지 않았으므로 자동 remediation은 시작하지 않는다.

## 집계 보정과 보존

첫 `CLEAN-002` 직후 join이 warm-up app log까지 포함하고 공백 구분 로그의 request ID를 과다 파싱하는 문제를 발견했다. 원본은 삭제하지 않았고, core `experimentRunId` 필터와 필드 파서를 보정한 동일 aggregator로 세 raw를 다시 집계했다. 이어 client abort 선행 판정이 request-aborted event만 보던 문제를 incomplete response-close까지 포함하도록 보정했다. 부하 실행은 추가하지 않았다.

core 시작 전 발생한 두 건은 performance run이 아니다.

- `SETUP-20260802-EXP111-PREEXEC-001`: artifact probe가 결과 폴더를 선점한 pre-execution failure
- `SETUP-20260802-EXP111-PREEXEC-002-WARMUP`: 기존 DB warm-up user prefix 충돌로 core 전 중단

두 setup artifact와 첫 VALID warm-up 원본은 로컬 결과 디렉터리에 보존했다.

## Evidence 위치

각 core 디렉터리:

- `experiment/results/RUN-20260802-EXP111-CLEAN-002/`
- `experiment/results/RUN-20260802-EXP111-CLEAN-003/`
- `experiment/results/RUN-20260802-EXP111-CLEAN-004/`

핵심 artifact:

- `correlation-summary.json`
- `correlation-join.jsonl`
- `connection-events.jsonl`
- `application.log`
- `mock-requests.json`
- `client-results.json`
- `verification-summary.json`
- `correlation-provenance.json`

원시 결과는 `.gitignore` 정책에 따라 Git commit에 강제 추가하지 않고 로컬 evidence로 보존한다.

## Follow-up candidate

필요한 경우에만 양단 connection을 직접 연결할 수 있는 socket tuple 기반 diagnostic 1회를 별도 사전등록한다. 자동 실행하지 않는다.
