# Exp161 Exp160 Transport Failure Attribution & Sink Mechanism Audit

## 감사 범위

- 신규 성능 실행: 없음
- 기준 run: `experiment/results/experiment-1-60/SINK-C400-Q3-R1`
- START_HEAD: `ad37460ef48b979dca4811c1cdf15ed66deacb8e`
- Exp160 aggregate와 summarizer의 runId가 모두 `SINK-C400-Q3-R1`임을 확인
- 원본 load 결과, application log, dispatcher snapshot, stage/pool/mock artifact와 현재 Sink 소스를 대조

## Transport failure breakdown

load raw의 `requests[].transport`를 authoritative source로 집계했다.

| category | phase | count | transport failures 비율 |
|---|---|---:|---:|
| `CONNECT_REFUSED` | `PHASE_FETCH_HEADERS` | 1,654 | 74.20% |
| `CLIENT_ABORT_DEADLINE` | `PHASE_FETCH_HEADERS` | 575 | 25.80% |
| 합계 |  | 2,229 | 100.00% |

`CONNECT_REFUSED`의 root code는 `ECONNREFUSED`이며 remote endpoint는 `127.0.0.1:18560`이다. 이 1,654건은 application log에서 request ID가 발견되지 않는다. 따라서 client가 application evidence를 받기 전에 ingress 연결을 거부당한 분류가 지지된다.

`CLIENT_ABORT_DEADLINE`은 `AbortError`, root code `20`, `PHASE_FETCH_HEADERS`로 기록되어 있다. 575건 모두 application log에 request ID가 존재한다. 해당 요청의 client latency 범위는 15,002~18,126ms이고 평균은 16,064.6ms이다. 이는 15초 client deadline에 의한 abort가 transport category로 기록된 경우이며, 이 자료만으로 underlying 연결 장애라고 해석하지 않는다.

### 시간대별 패턴

| load 경과 | 요청 | HTTP 200 | HTTP 500 | HTTP 503 | HTTP 504 | transport | refused | deadline abort |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 0–5s | 531 | 5 | 2 | 305 | 105 | 114 | 0 | 114 |
| 5–10s | 568 | 0 | 0 | 54 | 52 | 462 | 318 | 144 |
| 10–15s | 513 | 0 | 14 | 35 | 9 | 455 | 286 | 169 |
| 15–20s | 438 | 0 | 3 | 10 | 19 | 406 | 305 | 101 |
| 20–25s | 466 | 18 | 0 | 44 | 48 | 356 | 309 | 47 |
| 25–30s | 441 | 118 | 0 | 64 | 6 | 253 | 253 | 0 |

refused는 5초 이후 각 bucket에서 관찰되고, deadline abort는 초반부터 나타나며 25초 이후에는 관찰되지 않는다. 이는 두 범주를 하나의 원인으로 합칠 근거가 없음을 보여준다.

## Request-ID correlation

- transport failure 2,229건 중 application log request ID가 있는 건: 575건
- application log request ID가 없는 건: 1,654건
- `CONNECT_REFUSED`: 1,654건 모두 application evidence 없음
- `CLIENT_ABORT_DEADLINE`: 575건 모두 application evidence 있음

dispatcher artifact에는 request별 완료/실패 correlation이 보존되지 않아, 각 transport 요청을 TOKEN/AI/STORAGE dispatcher의 특정 단계까지 일대일로 연결할 수는 없다. 따라서 다음 범위까지만 주장한다.

- A(client started, application evidence 없음): 1,654건, `CONNECT_REFUSED`
- B(application evidence 있음): 575건, `CLIENT_ABORT_DEADLINE`
- C/D/E 단계 도달 여부: 현재 raw로는 확정 불가
- F(application completion 후 client transport failure): 현재 request-level completion correlation 부족으로 확정 불가

## Application/Mock error evidence

client raw의 HTTP 500은 19건이다. application log에는 `WebClientRequestException`과 함께 `Connection reset by peer` 및 `reactor.netty.http.client.PrematureCloseException`이 반복 기록된다. 로그의 500 error block 기준으로는 `PrematureCloseException` 47회, `Connection reset by peer` 1회가 관찰되지만, 로그 block 수는 request raw의 19건과 일치하지 않으므로 이를 1:1 request count로 사용하지 않는다.

확인되지 않은 원인:

- AI mock 500: 확인되지 않음
- Storage mock 500: 확인되지 않음
- DB error: 확인되지 않음
- `RejectedExecutionException`: 확인되지 않음
- `OutOfMemoryError`/container OOM/restart: 확인되지 않음

## Sink utilization and queue audit

현재 run의 dispatcher observation:

| dispatcher | configured concurrency | observed active peak | ceiling |
|---|---:|---:|---|
| TOKEN | 100 | 35 | `NO` |
| AI | 400 | 189 | `NO` |
| STORAGE | 100 | 42 | `NO` |

따라서 관측된 active 값만으로는 어떤 Sink도 설정 concurrency ceiling에 도달했다고 볼 수 없다.

1초 polling에서 queue peak/final은 TOKEN/AI/STORAGE 모두 `0/0`이었다. 다만 queue wait max는 TOKEN 약 3.669초, AI 약 0.252초, STORAGE 약 0.00364초였다. 따라서 polling peak 0만으로 queue가 한 번도 사용되지 않았다고 결론 내리지 않으며, queue wait가 존재했다는 사실만 보존한다. queue wait p50/p95/p99와 deadline phase별 metric은 현재 artifact에서 `NOT_AVAILABLE`이다.

## Dispatcher emission audit

load raw의 HTTP 503 본문에 다음이 직접 기록되어 있다.

```text
dispatcher queue rejected: dispatcher=<token|ai|storage>, ... emitResult=FAIL_NON_SERIALIZED
```

이 형태의 응답은 총 515건이며 dispatcher별로 TOKEN 283, AI 185, STORAGE 47건이다. 현재 source의 `AbstractSinkDispatcher.enqueue()`는 동시 요청 경로에서 `Sinks.Many.unicast().onBackpressureBuffer(queue)`에 `tryEmitNext`를 호출하고, `EmitResult` failure를 `DispatcherQueueRejectedException`으로 반환한다. 따라서 `FAIL_NON_SERIALIZED`는 단순 queue capacity 초과가 아니라 Sink emission 경로에서 실제 관찰된 failure signal이다.

dispatcher final snapshot의 available event tag에는 `enqueued`, `dequeued`, `completed`, `failed`, `cancelled`, `rejected`가 존재하지만 `result_emission_failed`의 tagged series는 수집되지 않았다. 이 계측 공백은 인정하되, 503 response body의 `FAIL_NON_SERIALIZED` 원본 증거 자체는 유효하다.

## Consumer termination 및 runtime thread 판단

application log에서 `dispatcher consumer terminated` 또는 token/ai/storage consumer의 unexpected terminal error는 확인되지 않았다. 따라서:

```text
DISPATCHER_CONSUMER_TERMINATION: NOT_SUPPORTED
```

현재 source에서 `dispatch()`는 `Mono.defer`로 enqueue를 지연하고, `tryEmitNext`는 호출 스레드에서 실행될 수 있으며, unicast sink는 producer 직렬화 실패를 반환할 수 있다. 이는 정적 메커니즘 설명으로는 가능하지만, 별도 runtime thread trace가 없으므로 event-loop가 직접 원인이라고 확정하지 않는다.

## Provider timeline

`provider-metrics.jsonl`은 초기 sample의 빈 metric과 이후 stringified metric view를 포함하지만, 안정적인 provider별 active/pending 시계열로 복구할 수 없다. `pool-final.json`의 종료 시점 snapshot은 존재하나 시간축 전체를 대표하지 않는다.

```text
PROVIDER_TIMELINE_RECOVERY: NOT_AVAILABLE
```

## 최종 판정

```text
SINK_E2E_PERFORMANCE: FAIL
SINK_MECHANISM_FAILURE: SUPPORTED
CLIENT_TO_APPLICATION_TRANSPORT_FAILURE: SUPPORTED
CLIENT_DEADLINE_ACCUMULATION: SUPPORTED
```

판정 근거:

1. 1,654건의 `ECONNREFUSED`가 application evidence 없이 발생하여 client-to-application ingress transport failure가 직접 관찰됐다.
2. 575건은 application evidence가 있는 `AbortError` deadline abort이며, 15초 ceiling을 넘긴 요청에서 발생했다.
3. 515건의 HTTP 503에 `FAIL_NON_SERIALIZED`가 직접 포함되어 있어 Sink emission failure가 구체적으로 입증된다.
4. active peak는 모든 dispatcher concurrency보다 낮고, consumer termination·OOM·mock crash 증거는 없다.

이번 audit만으로 1,654건 모두가 Sink 때문이라고 주장하지 않는다. `CONNECT_REFUSED`, client deadline accumulation, Sink emission failure는 서로 다른 관찰 범주이며 request-level stage correlation과 provider timeline은 부족하다.

## 다음 실험 분류

```text
NEXT_EXPERIMENT_CLASS: SINK IMPLEMENTATION REPAIR
NEXT_RECOMMENDED_STEP: FAIL_NON_SERIALIZED emission 경로를 수정 후보로 사전등록하고, ingress transport와 분리된 최소 재현 계획을 별도로 승인한 뒤 진행
```

현재 작업에서는 수정·재실행하지 않았다.

