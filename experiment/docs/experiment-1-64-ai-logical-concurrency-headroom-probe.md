# Exp164 — AI Logical Concurrency Headroom Probe

## 질문

Exp162 Q3 조건을 유지한 채 AI Sink 논리 동시성만 400에서 500으로 올리면, AI 단계의 추가 headroom이 성공 처리량과 deadline 압력을 개선하는가?

## 통제 조건

- source/harness commit: `aa28b7f481543ed99386a431bfa29fd797d15a22`
- AI/Storage mock: 2000ms / 100ms, 모두 HTTP 200
- active missions 200, 1초 간격, 30초 부하, 15초 drain
- application 2 CPU / 3 GiB, JVM `-Xms512m -Xmx2g -XX:+UseG1GC`
- provider pool: TOKEN 100/160, AI 600/960, STORAGE 100/160
- admission OFF, FIFO, 동일 Q3 queue 300/1200/300
- 유일한 변경: `sinkAiConcurrency=400 → 500`

## 실행 및 유효성

Smoke `SMOKE-EXP164-002`에서 rendered run-config의 source/harness provenance와 AI 500, Q3 queue를 확인했다. 본 실행 `SINK-C500-Q3-R1`은 `validity.json`에서 `valid=true`이며, warm-up·부하·drain·cleanup artifact를 모두 보존했다. 새 성능 run은 정확히 1회다.

## Exp162 대비 원본 결과

| 지표 | Exp162 C400 Q3 | Exp164 C500 Q3 |
|---|---:|---:|
| completed attempts | 5,908 | 5,933 |
| HTTP 200 accepted | 2,380 | 158 |
| accepted RPS | 79.33 | 5.27 |
| accepted p50 / p95 / p99 | 8,524 / 12,545 / 13,792 ms | 10,792 / 11,461 / 11,798 ms |
| HTTP 500 | 198 | 21 |
| downstream 503 | 2,180 | 2,640 |
| HTTP 504 | 1,016 | 3,073 |
| client deadline | 134 | 41 |
| max in-flight | 2,168 | 2,001 |

Exp164의 accepted latency p95만 보면 12,545→11,461ms로 낮아졌지만, 성공 표본이 2,380→158로 급감했으므로 처리량 개선으로 해석할 수 없다.

## Dispatcher·overflow 관측

- TOKEN: configured 100, active peak 100, queue peak 299, overflow 1,693
- AI: configured 500, active peak 500, queue peak 562, overflow 0
- STORAGE: configured 100, active peak 88, queue peak 300, overflow 947
- 모든 dispatcher의 최종 active/queue는 0이다.
- `FAIL_NON_SERIALIZED=0`; serialized emission 불변식은 유지됐다.
- queue wait duration metric은 이 경로에서 `NOT_AVAILABLE`이다.

## 자원·drain

- AI in-flight at load-stop 495, AI max in-flight 526; 500 논리 active에 실제 도달했다.
- storage in-flight at load-stop 23.
- drain completed=true, AI/Storage time-to-zero 10,008ms.
- application CPU 평균 74.87%, 관측 p95/peak 196.88% (2 CPU 컨테이너 기준), memory peak 2.332 GiB / 3 GiB.
- OOM 및 application restart는 관측되지 않았다.

## 최종 판정

`AI_LOGICAL_CONCURRENCY_SIGNAL=NOT_SUPPORTED`

AI active는 400에서 500까지 확장됐지만, accepted RPS가 79.33에서 5.27로 증가하지 않고 오히려 크게 감소했다. HTTP 504와 downstream 503이 증가했고 TOKEN/STORAGE overflow가 남아 있어, AI 논리 동시성 증가가 전체 경로의 완료 능력을 개선했다는 근거가 없다.

`AI_PHYSICAL_HEADROOM_USE=NOT_SUPPORTED`

AI active가 500을 사용한 사실은 확인되지만 completion improvement와 deadline pressure 완화가 함께 나타나지 않았다.

## 한계와 다음 단계

이 결과는 단일 Exp164 run과 Exp162의 유효 R2를 비교한 방향성 probe다. queue wait 분포, permit holding, 전체 request 단계별 tail은 이 하네스에서 직접 제공되지 않는다. 따라서 AI 자체가 유일한 병목이라고 주장하지 않으며, 이 probe만으로 AI 600 후속 실행도 승인하지 않는다.

Production Java 변경은 없다. Exp164 이후 추가 성능 실험은 별도 사전등록 없이는 수행하지 않는다.
