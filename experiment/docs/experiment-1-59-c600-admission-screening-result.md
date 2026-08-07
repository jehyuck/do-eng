# Exp159 C600 Admission Gate Capacity Screening Result

## 핵심 결과

고정된 200 VU·30초 workload에서 Exp158의 Admission OFF control(`C600-100-R1`)과 Gate 400/600/800을 비교했다. 세 Gate run 모두 실행·drain·permit accounting은 유효했지만, OFF control보다 accepted HTTP 200 완료율이 높아지지 않았다.

## 실행 및 자료

- START_HEAD: `b54181ea936344953b8b6a7f4f46d20068e84130`
- CONTROL_REUSE: `YES` (`experiment/results/experiment-1-58/C600-100-R1`)
- NEW PERFORMANCE RUN COUNT: `3`
- 순서: `G600 → G400 → G800`
- aggregate: `experiment/results/experiment-1-59/aggregate.json`
- Production Java change: `NONE`

## 결과 비교

| 조건 | accepted HTTP200/sec | 성공률 | HTTP200 p95 / p99 (ms) | HTTP500 | Admission503 | timeout | connection error | max in-flight | drain time-to-zero |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| OFF control | 134.27 | 67.50% | 13265 / 14329 | 1873 | 0 | 66 | 0 | 1530 | 3006ms |
| G400 | 9.43 | 4.95% | 14829 / 14962 | 200 | 3301 | 855 | 1082 | 1275 | 9016ms |
| G600 | 9.67 | 4.97% | 14817 / 14961 | 770 | 2211 | 1337 | 1228 | 1748 | 11001ms |
| G800 | 25.67 | 12.92% | 14149 / 14768 | 2286 | 1734 | 1034 | 136 | 2169 | 7011ms |

Gate accounting은 세 run 모두 `acquired = released`, `active final = 0`, `permitLeak = 0`이었다. 따라서 permit 누수로 인한 invalid는 없다. Drain도 모두 완료됐지만 OFF control보다 빨라졌다고 볼 수 없다.

container monitor에서 관측한 flux-corrected 자원 요약은 G400 CPU 평균/피크 `93.18%/219.66%`, G600 `107.50%/219.33%`, G800 `116.52%/210.52%`였다. 마지막 관측 memory는 각각 약 `1.144/1.81/2.109 GiB`(3 GiB limit)였고 restart/OOM은 없었다. 이 값은 collector 샘플 범위의 요약이며 포화 원인을 단독으로 확정하지 않는다.

## Gate 및 provider 관측

- G400: acquired 1318, rejected 3321, released 1318, active peak 400
- G600: acquired 2391, rejected 2217, released 2391, active peak 600
- G800: acquired 4090, rejected 1734, released 4090, active peak 800
- stage max in-flight(G400/G600/G800): TOKEN `284/560/686`, AI `347/361/447`, STORAGE `138/281/308`
- load-stop 이후 stage in-flight는 모두 0으로 회수됐다.
- pool final snapshot은 provider별 total/pending을 보존했으나, 1초 시계열 collector는 endpoint timeout으로 `NOT_AVAILABLE`이다. 따라서 provider pending peak이나 시간별 active 곡선은 이 실험에서 확정하지 않는다.

## 판정

```text
GATE_ACCOUNTING: PASS
ADMISSION_SIGNAL: NOT_SUPPORTED
ADMISSION_WINNER: OFF
TIME_DEPENDENT_BACKLOG_REDUCTION: NOT_SUPPORTED
CONFIRMATION_RUN: NO
CONFIRMATION_RESULT: NOT_RUN
BEST_OBSERVED_WEBFLUX_CONFIGURATION: provider 100/600/100 + Admission OFF (Exp158 C600-100-R1 control)
NEXT_FLOW_CONTROL: INCONCLUSIVE
NEXT_RECOMMENDED_STEP: 추가 Gate grid나 confirmation을 실행하지 않고, provider 시계열 계측 공백과 workload 범위만 기록
```

Gate 800은 Gate 400/600보다 accepted 완료율이 높았지만 OFF control보다 크게 낮고 timeout·connection error가 증가했다. 그러므로 Gate가 이 workload에서 accepted 처리량을 개선했다거나 600/800을 최적값이라고 주장할 수 없다. 이번 결과는 Admission 효과가 `NOT_SUPPORTED`인 단일 screening cohort의 관찰이며, 운영 환경 일반론이나 WebFlux·MVC 비교 결론이 아니다.
