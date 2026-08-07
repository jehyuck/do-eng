# Exp157 Fast Static Flow Balance Screening 계획

## 질문

Exp156에서 관찰된 WebFlux 압력이 AI capacity 자체인지, TOKEN/AI/STORAGE의 정적 capacity 균형 문제인지 빠르게 구분한다.

## 고정 조건

- WebFlux, VU 200, staggered 200 users, 1초 간격
- load 15초, drain 최대 10초, request timeout 15초
- AI mock 2000ms/HTTP 200, storage mock 100ms/HTTP 200
- application 2 CPU/3 GiB, JVM Xms512m/Xmx2g/G1GC, DB pool 10
- Admission OFF, Sink OFF, pending acquire timeout 10초
- 동일 source commit `507e075016728daeaab75a51e7172577efe4c5ce`, 동일 fixture
- 각 cell fresh recreate, 순서: Q600 → Q700-B150 → Q700-U100 → Q700-B200

## 변경 조건

| cell | TOKEN | AI | STORAGE |
|---|---:|---:|---:|
| Q600 | 100 | 600 | 100 |
| Q700-B150 | 150 | 700 | 150 |
| Q700-U100 | 100 | 700 | 100 |
| Q700-B200 | 200 | 700 | 200 |

각 isolated provider의 pending max는 capacity × 1.6, shared pool budget은 세 provider 합계로 설정한다.

## 측정

accepted HTTP 200/sec를 primary로 사용하고, success rate, HTTP 200 p50/p95/p99, HTTP 500/503, timeout, connection error, completed/sec, maxInFlight를 함께 기록한다. TOKEN/AI/STORAGE별 active/pending, application CPU·memory·PIDs, restart/OOM도 보존한다.

## 판정

- balanced 700 cell이 Q600보다 반복적으로 개선되면 `STATIC_BALANCE_SIGNAL=SUPPORTED`
- Q600이 모든 700 cell보다 낫다면 `NOT_SUPPORTED`
- 방향이 충돌하면 `INCONCLUSIVE`

winner가 Q600보다 명확히 좋고 CPU/OOM/restart/tail/DB integrity 문제가 없을 때만 VU200 30초 confirmation 1회를 허용한다. 추가 grid search는 수행하지 않는다. 동적 flow-aware concurrency 구현은 하지 않고 결과에 따라 정당화 여부만 기록한다.

## 산출물

- `experiment/scripts/run-exp157-flow-balance.ps1`
- `experiment/scripts/summarize-exp157-flow-balance.ps1`
- `experiment/docs/experiment-1-57-fast-static-flow-balance-result.md`
- `experiment/results/experiment-1-57/`
