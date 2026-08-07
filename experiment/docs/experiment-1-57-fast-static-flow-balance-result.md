# Exp157 Fast Static Flow Balance 결과

## 실행 범위

- 기준 시작 HEAD: `be8481aa841126b8b0da5e14a3b51831403ee634`
- WebFlux VU200, staggered 1초 간격, 15초 load와 10초 drain을 사용했다.
- 모든 cell은 fresh recreate로 실행했고 source, fixture, mock delay, timeout, CPU/memory, DB pool, Admission OFF, Sink OFF를 고정했다.
- 새 performance run은 4회이며, MVC·Sink·Admission 비교와 production Java 변경은 없었다.

## Phase A — Exp156 raw pressure 재분석

기존 C600-S1, C600-R2, C600-R3, C700-S1의 `application-resources.jsonl`, `provider-metrics.jsonl`, `stage-final.json`, `pool-final.json`을 다시 읽었다. provider metric은 TOKEN/AI/STORAGE tag로 분리했고, stage-final은 세 stage의 in-flight와 duration tail을 분리했다.

| 판정 | 결과 | 근거 |
|---|---|---|
| CPU_SATURATION | INCONCLUSIVE | C600 peak 242.05%, C700 peak 220.07%였지만 2 CPU ceiling의 지속 포화 시계열은 확보되지 않음 |
| PRESSURE_SHIFT | INCONCLUSIVE | AI pending은 C600 960, C700 1120으로 상한에 닿았으나 TOKEN/STORAGE와 CPU의 인과적 pressure shift를 한 쌍의 raw만으로 분리할 수 없음 |
| AI_CONNECTION_CEILING | NOT_REACHED | C600 AI active peak 228, C700 AI active peak 254로 각각 configured max 600/700에 도달하지 않음 |

Stage attribution 자체는 가능했다. 다만 pending이 configured max pending에 도달한 사실만으로 connection ceiling 또는 단일 root cause를 확정하지 않았다.

## Phase B — 4-cell screening

| cell | TOKEN/AI/STORAGE | accepted HTTP 200/sec | success rate | HTTP 200 p95/p99 | timeout | HTTP 500 | CPU peak | memory peak |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Q600 | 100/600/100 | 98.33 | 49.40% | 12,264 / 14,462 ms | 2 | 1,509 | 198.42% | 876.5 MiB |
| Q700-B150 | 150/700/150 | 44.87 | 22.73% | 14,791 / 14,966 ms | 999 | 1,289 | 209.43% | 931.1 MiB |
| Q700-U100 | 100/700/100 | 49.80 | 25.04% | 14,661 / 14,963 ms | 573 | 1,663 | 217.13% | 488.0 MiB |
| Q700-B200 | 200/700/200 | 33.20 | 17.72% | 14,924 / 14,989 ms | 1,605 | 708 | 207.96% | 765.3 MiB |

각 run의 provider metric은 numeric sample을 확보했다. Q600의 AI active peak는 562, pending peak는 960이었다. Q700-B150/U100/B200의 AI active peak는 각각 405/377/459, pending peak는 모두 1120이었다. TOKEN과 STORAGE pending도 각 cell의 관측값으로 보존했으며, 별도의 추정값을 만들지 않았다.

## Screening 판정

```text
STATIC_BALANCE_SIGNAL = NOT_SUPPORTED
SCREENING_WINNER = Q600
CONFIRMATION_RUN = NO
CONFIRMATION_RESULT = NOT_RUN
```

Q600이 세 Q700 cell보다 accepted HTTP 200/sec, success rate, p95에서 모두 우세했다. 따라서 700 계열의 static balance 조정이 개선 신호를 만들었다고 볼 수 없다. 사전등록된 confirmation 조건(700 cell이 Q600보다 명확히 우수)을 충족하지 않아 confirmation은 실행하지 않았다.

## 최종 결정

```text
EXP157_DECISION:
STATIC_POOL_FURTHER_TUNING = LOW_VALUE
FLOW_AWARE_LOGICAL_CONCURRENCY = NOT_JUSTIFIED
BEST_OBSERVED_STATIC_CONFIGURATION = Q600 (100/600/100)
NEW_PERFORMANCE_RUN_COUNT = 4
PRODUCTION_JAVA_CHANGE = NONE
```

이번 결과는 Q600이 이 짧은 synthetic screening에서 가장 나았다는 뜻이다. 최적 provider capacity, WebFlux의 일반적 우위, CPU·TOKEN·STORAGE 중 하나의 확정 root cause, 동적 concurrency의 필요성을 증명하지 않는다. Static grid search는 여기서 종료하며, 동적 제어 구현은 별도 사전등록 없이는 시작하지 않는다.
