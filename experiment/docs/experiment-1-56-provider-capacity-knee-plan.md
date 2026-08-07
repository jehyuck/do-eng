# Exp156 Provider Capacity Knee Search Plan

## 질문

고정된 VU200 WebFlux workload에서 AI provider max connections를 400, 500, 600(조건부 700)으로 바꿀 때 HTTP 200 accepted completion rate가 증가하는지와 증가가 멈추는 knee를 관찰한다.

## 고정 조건

- 200 active missions, staggered, 1초 간격, 30초
- AI mock 2,000ms / HTTP 200, storage mock 100ms / HTTP 200
- application 2 CPU / 3 GiB, JVM Xms512m/Xmx2g/G1GC, DB pool 10
- ISOLATED provider; TOKEN 100/160, STORAGE 100/160, Admission OFF, Sink OFF
- client timeout 15초, pending acquire timeout 10초
- fixture `image/arc.jpg`, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- production source/image, workload, mock, timeout, resource, DB, scheduler 변경 없음

## 변경 조건

AI provider만 다음처럼 변경한다.

| cell | AI max | AI pending max |
|---|---:|---:|
| C400 | 400 | 640 |
| C500 | 500 | 800 |
| C600 | 600 | 960 |
| C700 (조건부) | 700 | 1120 |

## 실행

1. Screening: C400-S1, C500-S1, C600-S1
2. C600이 C500보다 accepted completion rate가 명확히 증가하고 CPU/memory/restart/OOM/downstream/DB가 안정적이면 C700-S1을 추가한다.
3. 최종 후보 두 개를 crossover 순서로 각 3 valid run까지 반복한다.

Primary metric은 `acceptedCompletionsPerLoadSecond = HTTP_200_ACCEPTED / configured load duration`이다. `completedPerLoadSecond`는 모든 completed response의 처리량으로 별도 보존한다. latency는 all-response와 HTTP 200-only를 분리한다.

## 종료·판정

관찰 가능한 최선의 정적 capacity만 `BEST_OBSERVED_STATIC_CAPACITY`로 표현한다. 최적값·운영 보편성은 주장하지 않는다. provider pending/acquire 또는 downstream queue의 직접 시계열이 복구되지 않으면 해당 근거는 `NOT_RECOVERABLE_FROM_EXISTING_ARTIFACT`로 기록한다.
