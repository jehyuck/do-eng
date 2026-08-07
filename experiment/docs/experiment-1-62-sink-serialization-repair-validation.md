# Exp162 Sink Serialized Emission Repair Validation

## 실행 기준

- START_HEAD: `0ea99dbc8f6775ade817b4e12856dcc9556456c7`
- production source/image: current HEAD에서 fresh build
- 단위 테스트: `AbstractSinkDispatcherTest` 전체 PASS
- 설정: Exp160과 동일
- 유효 run: `SINK-C400-Q3-SERIALIZED-R2`
- `SINK-C400-Q3-SERIALIZED-R1`은 부하와 artifact는 완료됐으나 `sourceCommit` provenance가 이전 `cf5b36a`로 남아 유효 결과에서 제외했다. 원본은 보존한다.

## 변경 경계

이번 검증에서 유일한 production 변경은 `AbstractSinkDispatcher`의 `Sinks.Many` emission 경계 직렬화다. provider pool, Sink concurrency/queue, Admission, workload, timeout, mock delay, DB pool, CPU/memory는 Exp160과 동일하다.

## Broken Exp160 대비 결과

| 항목 | Exp160 broken | Exp162 serialized R2 |
|---|---:|---:|
| attempted requests | 3,146 | 5,908 |
| HTTP 200 | 144 | 2,380 |
| accepted HTTP200/sec | 4.80 | 79.33 |
| success rate | 4.58% | 40.28% |
| HTTP 500 | 19 | 198 |
| HTTP 503 downstream | 515 (`FAIL_NON_SERIALIZED`) | 2,180 (`FAIL_OVERFLOW`) |
| HTTP 504 | 239 | 1,016 |
| client deadline abort | 575 | 134 |
| `CONNECT_REFUSED` | 1,654 | 0 |
| overall p95 | 14,837ms (HTTP200 p95) | 12,634ms |
| overall p99 | 14,984ms (HTTP200 p99) | 14,497ms |
| max in-flight | 857 | 2,168 |

성공 처리량은 개선됐지만, Exp160과 실행 시점·provenance가 완전히 동일한 matched control이 아니므로 이 표만으로 일반 성능 개선이나 production adoption을 주장하지 않는다.

## Primary repair criterion

유효 run의 2,180건 HTTP 503 본문을 모두 확인했다.

```text
FAIL_NON_SERIALIZED_AFTER_REPAIR = 0
FAIL_OVERFLOW = 2180
OTHER_EMIT_FAILURE = 0
```

`FAIL_OVERFLOW`는 TOKEN 1,869건, STORAGE 311건이다. 이는 serialization defect가 제거된 뒤 bounded queue pressure가 노출된 결과이며 `FAIL_NON_SERIALIZED`와 동일한 원인으로 합산하지 않는다.

## Transport attribution

유효 run의 transport failure는 134건이며 모두 다음과 같다.

```text
CLIENT_ABORT_DEADLINE: 134
PHASE_FETCH_HEADERS: 134
CONNECT_REFUSED: 0
CONNECT_TIMEOUT: 0
SOCKET_RESET: 0
SOCKET_CLOSED: 0
```

따라서 이번 단일 repaired run에서 `CONNECT_REFUSED`는 관찰되지 않았다. 다만 단일 run의 결과이므로 host/listener 문제의 일반적 해결을 확정하지 않는다.

## Dispatcher 관측

| dispatcher | concurrency | active peak | queue sampled peak | final queue | queue wait max |
|---|---:|---:|---:|---:|---:|
| TOKEN | 100 | 100 | 289 | 0 | `NOT_AVAILABLE` |
| AI | 400 | 400 | 647 | 0 | `NOT_AVAILABLE` |
| STORAGE | 100 | 100 | 299 | 0 | `NOT_AVAILABLE` |

1초 polling queue peak은 순간 상태의 표본이며, queue wait percentile/max는 해당 endpoint에서 수집되지 않았다. 종료 시 queue와 downstream in-flight는 0이었다.

consumer termination 로그는 발견되지 않았다.

## Resource safety

- application CPU: 평균 48.96%, p95 199.66%, peak 205.80%
- application memory peak: 약 2.226GiB / 3GiB
- application restart: 없음
- OOM: 없음
- drain: 완료, AI/storage time-to-zero 약 8,001ms
- provider active/pending timeline: `NOT_AVAILABLE`

## 판정 Gate

```text
SINK_SERIALIZATION_REPAIR: PASS
INGRESS_CONNECT_REFUSED_AFTER_REPAIR: RESOLVED
SINK_E2E_RECOVERY_SIGNAL: SUPPORTED (single-run directional evidence)
```

근거는 `FAIL_NON_SERIALIZED`가 515건에서 0건으로 사라지고, `CONNECT_REFUSED`가 1,654건에서 0건으로 관찰된 점이다. 동시에 `FAIL_OVERFLOW` 2,180건과 HTTP 504 1,016건이 남아 있어 전체 요청 경로가 해결됐다고 보지 않는다.

## 다음 단계

```text
NEXT_EXPERIMENT_CLASS: BOUNDED QUEUE PRESSURE REVIEW
NEXT_RECOMMENDED_STEP: FAIL_OVERFLOW를 serialization failure와 분리한 채, 별도 승인된 최소 queue-pressure 진단을 설계
```

추가 Sink tuning, queue grid, production adoption, matched OFF 비교는 이번 작업에서 수행하지 않았다.

