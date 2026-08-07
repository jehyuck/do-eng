# Exp158 C600 Static Balance Closure 계획

## 질문

AI provider를 600으로 고정하고 TOKEN/STORAGE를 100, 150, 200으로 늘릴 때 accepted HTTP 200 completion rate가 개선되는지, 30초 workload 안에서 time-dependent degradation/backlog이 나타나는지 확인한다.

## 고정 조건

- WebFlux VU200, staggered, 1초 간격, 30초 load, 15초 drain
- AI 2000ms/HTTP 200, storage 100ms/HTTP 200
- application 2 CPU/3 GiB, JVM Xms512m/Xmx2g/G1GC, DB pool 10
- ISOLATED provider mode, Admission OFF, Sink OFF, pending acquire timeout 10초
- 동일 source `507e075016728daeaab75a51e7172577efe4c5ce`, fixture, image, DB seed, client timeout
- 실행 순서: C600-100 → C600-200 → C600-150

## 변경 조건

| cell | TOKEN | AI | STORAGE |
|---|---:|---:|---:|
| C600-100 | 100 | 600 | 100 |
| C600-200 | 200 | 600 | 200 |
| C600-150 | 150 | 600 | 150 |

각 provider pending max는 1.6배로 유지한다. Main run은 cell당 1회이며, 명확한 winner가 있을 때만 winner confirmation 1회를 허용한다.

## 측정 및 판정

전체 결과는 accepted HTTP 200/sec, 성공률, HTTP 200 p50/p95/p99/max, HTTP 500/503, timeout, connection error, completed/sec, maxInFlight로 기록한다. TOKEN/AI/STORAGE별 active·pending의 avg/p95/peak/non-zero sample, application CPU·memory·PIDs·restart/OOM을 분리한다.

30초를 T0~T5(각 5초)로 나누어 가능한 raw timestamp로 accepted count/rate, 실패, provider pending, in-flight, CPU·memory를 계산한다. 직접 계산할 수 없는 bucket은 추정하지 않는다.

결과가 비슷하거나 C600-100이 우세하면 confirmation 없이 종료한다. 이번 실험에서는 dynamic controller, Admission/Sink tuning, 추가 grid search를 수행하지 않는다.
