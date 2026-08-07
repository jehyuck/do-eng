# Exp158 C600 Static Balance 결과

## 실행 및 유효성

- 시작 HEAD: `fe4e439f28983b8d706b53e5c3bee779f7990270`
- 최초 C600-100/C600-200/C600-150 실행은 하네스 치환 오류로 `200/700/200` 설정이 렌더링되어 무효 처리했다. 원본은 삭제·수정하지 않고 제외했다.
- 수정 후 `C600-100-R1`, `C600-200-R1`, `C600-150-R1`을 동일한 30초 계약으로 교체 실행했고 세 run 모두 valid artifact를 확보했다.
- 따라서 실제 조건을 충족한 신규 performance run은 3회이며, confirmation은 실행하지 않았다.

## 전체 결과

| configuration | accepted HTTP 200/sec | success rate | HTTP 200 p95/p99 | HTTP 500 | timeout | CPU avg/p95/peak | memory peak |
|---|---:|---:|---:|---:|---:|---:|---:|
| C600-100 (100/600/100) | 134.27 | 67.50% | 13,265 / 14,329ms | 1,873 | 66 | 107.27 / 208.60 / 208.60% | 885.2MiB |
| C600-200 (200/600/200) | 134.83 | 67.80% | 11,657 / 14,133ms | 1,210 | 711 | 107.73 / 207.61 / 207.61% | 836.1MiB |
| C600-150 (150/600/150) | 82.90 | 41.74% | 13,601 / 14,710ms | 2,583 | 888 | 114.25 / 210.85 / 210.85% | 1,012.0MiB |

C600-200은 primary accepted rate가 C600-100보다 0.56/sec 높았지만, 명확한 개선으로 볼 수준의 차이는 아니었다. p95와 HTTP 500은 낮아졌지만 timeout은 증가했다. C600-150은 전반적으로 악화됐다.

## Stage별 provider 관측

| cell | TOKEN active peak / pending peak | AI active peak / pending peak | STORAGE active peak / pending peak |
|---|---:|---:|---:|
| C600-100 | 88 / 743 | 562 / 960 | 100 / 191 |
| C600-200 | 200 / 778 | 600 / 960 | 200 / 320 |
| C600-150 | 140 / 609 | 502 / 960 | 150 / 240 |

AI pending은 세 run 모두 960에 도달했지만 AI active가 configured max를 일관되게 초과하지 않았다. 이 결과만으로 AI connection ceiling 또는 단일 root cause를 확정하지 않는다.

## 30초 time-bucket

| cell | bucket | accepted HTTP 200/sec | HTTP 500 | timeout | CPU | TOKEN pending | AI pending | STORAGE pending | max in-flight |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| C600-100 | T0/T1/T2/T3/T4/T5 | 3.4 / 40.2 / 73.6 / 125.8 / 226.6 / 220.2 | 0 / 332 / 732 / 724 / 85 / 0 | 0 / 0 / 0 / 0 / 0 / 0 | 200.14 / 208.60 / 196.91 / 199.98 / 199.42 / 196.83 | 160 / 160 / 743 / 160 / 160 / 160 | 960 / 960 / 960 / 960 / 960 / 960 | 160 / 191 / 160 / 160 / 160 / 160 | 525 / 305 / 770 / 690 / 559 / 461 |
| C600-200 | T0/T1/T2/T3/T4/T5 | 1.8 / 54.6 / 141.6 / 120.8 / 83.6 / 112.0 | 0 / 0 / 2 / 417 / 770 / 21 | 0 / 0 / 0 / 0 / 0 / 0 | 195.37 / 200.99 / 199.82 / 203.06 / 207.61 / 200.17 | 320 / 320 / 320 / 778 / 646 / 320 | 960 / 960 / 960 / 960 / 960 / 960 | 320 / 320 / 320 / 320 / 320 / 320 | 515 / 304 / 643 / 882 / 707 / 827 |
| C600-150 | T0/T1/T2/T3/T4/T5 | 0.0 / 29.4 / 79.6 / 91.6 / 32.8 / 66.4 | 0 / 33 / 355 / 729 / 233 / 781 | 0 / 0 / 0 / 0 / 0 / 0 | 199.07 / 199.42 / 197.09 / 199.89 / 206.08 / NOT_AVAILABLE | 240 / 240 / 252 / 609 / 240 / NOT_AVAILABLE | 960 / 960 / 960 / 960 / 960 / NOT_AVAILABLE | 240 / 240 / 240 / 240 / 240 / NOT_AVAILABLE | 520 / 347 / 512 / 654 / 729 / NOT_AVAILABLE |

## Degradation 및 backlog

```text
TIME_DEPENDENT_DEGRADATION = SUPPORTED
BACKLOG_ACCUMULATION = SUPPORTED
```

C600-200은 T2 이후 accepted rate가 141.6에서 83.6/sec로 감소하면서 max in-flight가 643→882→707→827로 증가했고, TOKEN/STORAGE pending이 상한에 머물렀다. C600-150도 T3 이후 accepted rate가 감소하고 in-flight가 증가했다. 반면 C600-100 control은 후반 accepted rate가 증가했으므로 degradation은 모든 configuration의 보편 현상이 아니라 일부 균형 조건에서 관찰된 시간 의존 신호다.

이는 backlog와 처리 저하의 동시 관측을 의미하지만, CPU·pending 중 하나가 단독 root cause라는 뜻은 아니다.

## 최종 판정

```text
STATIC_C600_BALANCE = NOT_SUPPORTED
SCREENING_WINNER = C600-200 (narrow primary-only observation)
CONFIRMATION_RUN = NO
CONFIRMATION_RESULT = NOT_RUN
BEST_OBSERVED_STATIC_CONFIGURATION = 100/600/100 control retained; C600-200 is a near tie
STATIC_POOL_SEARCH = CLOSED
NEXT_CONTROL_STRATEGY = INCONCLUSIVE
```

C600-200의 accepted rate 차이는 작고 timeout은 더 많았으므로 명확한 winner confirmation 조건을 충족하지 않았다. 100/600/100을 비교 기준으로 유지하고 static 숫자 탐색은 종료한다.

## 주장 범위

이번 결과는 고정된 WebFlux synthetic workload에서 일부 30초 구간의 pending/in-flight 누적과 accepted 처리 저하가 관찰됐다는 사실만 지지한다. 운영 최적 capacity, CPU 또는 pending의 확정 root cause, 동적 concurrency나 Admission의 필요성을 증명하지 않는다. 추가 dynamic control 실험은 별도 계획 없이는 시작하지 않는다.
