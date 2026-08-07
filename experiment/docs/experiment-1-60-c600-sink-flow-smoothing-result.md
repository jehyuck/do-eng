# Exp160 C600 Sink Flow-Smoothing Revalidation Result

## 실행 기준

- START_HEAD: `2313b10a14c850a8992dfbc5d567f4b9a2b02244`
- CONTROL_REUSE: `YES` (`Exp158 C600-100-R1`)
- 신규 본 실행: `SINK-C400-Q3-R1` 1회
- `SINK-C400-Q3`는 runner provenance에 AI pool 400/640이 남은 harness-invalid run으로 보존하고 집계에서 제외했다.
- Production business logic change: `NONE`
- instrumentation: Exp160 runner-level dispatcher collector와 snapshot 추가

## 고정 Sink 설정

```text
physical provider: TOKEN 100/160, AI 600/960, STORAGE 100/160
logical concurrency: TOKEN 100, AI 400, STORAGE 100
queue capacity: TOKEN 300, AI 1200, STORAGE 300
Admission: OFF
AI delay: 2000ms
Storage delay: 100ms
VU: 200, staggered, 1s, 30s load, 15s drain
```

## 결과

| 항목 | OFF control | Sink C400-Q3 |
|---|---:|---:|
| accepted HTTP200/sec | 134.27 | 4.80 |
| success rate | 67.50% | 4.58% |
| HTTP200 p95 | 13265ms | 14837ms |
| HTTP500 | 1873 | 19 |
| timeout | 66 | 575 |
| connection error | 0 | 1654 |
| max in-flight | 1530 | 857 |

Sink run은 load 결과와 drain이 유효했고 application/mock restart·OOM은 없었다. load-stop 당시 AI in-flight 105, 15초 drain 후 0, time-to-zero 약 8000ms였다.

## Sink 관측

- TOKEN queue peak/final: `0 / 0`, active peak/final: `35 / 0`
- AI queue peak/final: `0 / 0`, active peak/final: `189 / 0`
- STORAGE queue peak/final: `0 / 0`, active peak/final: `42 / 0`
- dispatcher cumulative snapshot은 token/ai/storage별 enqueued·dequeued·completed·failed·rejected 이벤트를 보존했다.
- queue wait p50/p95/p99는 Timer 원본에 percentile이 없어 `NOT_AVAILABLE`; max는 token `3.669s`, AI `0.252s`, storage `0.003638s`였다.
- deadline phase별 수치는 endpoint에 phase tag를 직접 조회하지 않아 `NOT_AVAILABLE`이다.
- provider active/pending 시계열은 Exp159와 같은 endpoint 수집 공백으로 `NOT_AVAILABLE`; pool final snapshot만 보존했다.

## 최종 판정

```text
SINK_COMPLETION_SIGNAL: NOT_SUPPORTED
FLOW_SMOOTHING_SIGNAL: INCONCLUSIVE
BACKLOG_RELOCATION_ONLY: INCONCLUSIVE
SINK_REVALIDATION: FAIL
NEXT_RECOMMENDED_STEP: Sink concurrency/queue grid 및 production 채택을 진행하지 않고, 이번 단일 결과와 provider 계측 공백을 보존
```

## 제한

`SINK-C400-Q3-R1`은 source/application image는 고정했지만 Exp160 runner의 provenance 보강 변경이 아직 커밋되기 전 실행됐다. 따라서 harness 변경 자체의 독립적인 commit identity는 raw run-config에 남지 않는다. 이 사실은 성능 결과를 무효화하는 production 변경이 아니라 계측 provenance 제한으로 보존한다.

Sink queue가 bounded되고 drain된 사실은 확인했지만, accepted completion은 control보다 크게 낮고 timeout·connection error가 증가했다. 따라서 이 run으로 Sink가 flow smoothing 또는 성능 개선을 제공한다고 주장할 수 없다. queue가 provider pending을 대체했다는 인과도 provider 시계열 부재로 확정하지 않는다.
