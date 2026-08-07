# Exp156 Provider Capacity Knee 결과

## 1. 실험 범위

- 기준 HEAD: `a875f50974611ec4361e86ddced0af95b1d880a1`
- WebFlux 고정 부하에서 AI provider capacity만 C400/C500/C600/C700로 변경했다.
- workload, AI/storage 지연, 애플리케이션 자원, DB pool, timeout, admission/sink 상태는 고정했다.
- MVC, Sink, Admission 비교와 production Java 변경은 수행하지 않았다.

## 2. 실행 및 유효성

초기 두 실행은 성능 결과가 아니라 하네스 계약 실패로 제외했다.

| run | 상태 | 제외 사유 |
|---|---|---|
| C400-S1 | 제외 | 포트 매핑 하네스 오류 |
| C500-S1 | 제외 | isolated pool 합계와 shared budget 불일치 |

최종 후보 세트는 C400 3회(`C400-S2`, `C400-R2`, `C400-R3`)와 C600 3회(`C600-S1`, `C600-R2`, `C600-R3`)다. 여섯 run 모두 raw validity와 필수 artifact 검증을 통과했고, 원본 제외 artifact도 보존했다.

## 3. Screening

| capacity | 유효 run | successful HTTP 200/sec | completed/sec | HTTP 200 p95 |
|---|---:|---:|---:|---:|
| C400 | 3 | 0.80 / 2.27 / 1.60 | 91.13 / 139.33 / 151.87 | 14995 / 14927 / 14923 ms |
| C500 | 1 | 0.47 | 122.03 | 14956 ms |
| C600 | 3 | 2.57 / 2.67 / 4.53 | 126.20 / 142.73 / 144.87 | 14920 / 14209 / 14789 ms |
| C700 | 1 | 0.10 | 131.13 | 14889 ms |

C600이 C500보다 screening에서 개선되어 C700을 확인했으나, C700은 성공 HTTP 200/sec가 낮았고 tail/resource 측면의 보상도 확인되지 않아 더 높은 capacity는 채택하지 않았다.

## 4. 최종 후보 집계

| 지표 | C400 중앙값 | C600 중앙값 |
|---|---:|---:|
| successful HTTP 200/sec | 1.60 | 2.67 |
| completed/sec | 139.33 | 142.73 |
| 성공률 | 1.05% | 2.03% |
| HTTP 200 p95 | 14927 ms | 14209 ms |
| HTTP 200 p99 | 14971 ms | 14842 ms |
| all-request p95 | 14965 ms | 14762 ms |
| client timeout 중앙값 | 2048 | 2235 |
| connection error 중앙값 | 1654 | 1351 |
| provider active peak 중앙값 | 281 | 284 |
| provider pending peak 중앙값 | 312 | 403 |

C600은 최종 후보 세트에서 successful HTTP 200 completion rate와 HTTP 200 p95의 관측 중앙값이 가장 좋았다. 다만 run 간 성공률과 pending peak의 편차가 있고, 모든 요청의 높은 tail과 실패가 해소된 것은 아니다.

## 5. 자원 및 downstream 관찰

최종 후보에서 관찰된 application 최대치는 다음 범위였다.

- CPU: 약 199~242% (2 CPU 제한 내)
- container memory: 약 621~1008 MiB (3 GiB 제한 내)
- application restart/OOM: 관찰되지 않음
- provider metric timeline: 여섯 run 모두 numeric sample 확보(`PASS`)

provider pending은 일부 시점에 관찰됐지만 run별 peak가 일관되게 증가하지 않았고, load-stop 시점의 최종 pending은 0이었다. 현재 artifact만으로 connection acquire timeout, socket failure 또는 Token/Storage 단독 포화를 직접 분리할 수 없다. DB artifact는 reachability 수준만 확인하며 semantic consistency를 주장하지 않는다.

## 6. 최종 판정

```text
BEST_OBSERVED_STATIC_CAPACITY
bestObserved = C600
TOKEN_STORAGE_FOLLOWUP = NO
```

이는 C600이 이번 고정 synthetic workload에서 가장 나은 관측 결과를 보였다는 의미이며, 운영 최적값이나 일반적인 pool/provider 권장값을 뜻하지 않는다. C700 screening은 C600 대비 successful HTTP 200/sec가 낮고 보상적인 tail/resource 개선이 없어 다음 단계로 진행하지 않았다.

## 7. 주장 범위와 한계

직접 주장할 수 있는 범위는 고정된 WebFlux synthetic workload에서 AI provider capacity 후보를 비교한 결과 C600이 가장 나은 관측값을 보였다는 사실까지다. MVC·Sink·Admission과의 우열, 운영 환경 일반화, 최적 capacity, 인과적 병목 확정은 이 실험에서 증명하지 않았다.

## 8. 후속 작업

추가 TOKEN/STORAGE follow-up은 사전 기준상 수행하지 않는다. 다음 검증이 필요하다면 C600을 기준으로 별도 계획을 만들고, capacity 결과와 Admission/Sink 정책 효과를 한 실험에서 섞지 않는다.
