# Experiment 1-7 Run Ledger Addendum

## 목적

Experiment 1-6의 최종 분류 B(계측 부족)를 유지한 채,
`reactor.netty.connection.provider.pending.connections.time`의
runtime 노출 여부만 확인하는 diagnostic pair를 기록한다. 성능 튜닝,
MVC 비교, full core cohort가 아니다.

## 고정 조건

- implementation: corrected WebFlux
- VU: 200, initial active users: 200
- frame/reconnect pacing: 1,000ms
- duration: 105s, request timeout: 10s
- AI delay: pair variable 1,000ms / 500ms
- storage delay: 100ms
- FULL_PATH admission: 320
- outbound HTTP pool: 400
- DB pool: 10
- application: 2 CPU / 3 GiB
- same fixture/auth/payload/completion contract, fresh JVM
- application/mock continuous snapshot: OFF
- JFR: OFF
- DB/container monitor: ON
- load-stop snapshot and 30s drain: ON

## Runs

| Run ID | warm-up | raw result path | Measurement Validity | System Outcome 요약 |
|---|---|---|---|---|
| `RUN-20260801-EXP17-AI1000-DIAG-001` | `SMOKE-RUN-20260801-EXP17-AI1000-DIAG-001` | `experiment/results/RUN-20260801-EXP17-AI1000-DIAG-001/` | VALID | success 13,222; controlled 503 7,199; HTTP 500 5; accepted p95/p99 3,950/8,008ms; pool pending max 19; drain 2,007ms |
| `RUN-20260801-EXP17-AI500-DIAG-001` | `SMOKE-RUN-20260801-EXP17-AI500-DIAG-001` | `experiment/results/RUN-20260801-EXP17-AI500-DIAG-001/` | VALID | success 12,069; controlled 503 8,296; HTTP 500 0; accepted p95/p99 6,224/8,944ms; pool pending max 42; drain 2,000ms |

## 계측 결과

두 run의 `pool-metrics.jsonl`에서
`reactor.netty.connection.provider.pending.connections.time` Timer row는
각각 0개였다. Gauge 기반 active/idle/total/pending/max 값은 보존됐지만
connection acquire 대기시간 count/total/mean/max/percentile은
`NOT AVAILABLE`이다. Timer 부재는 pair를 invalid 처리하지 않고 결과 문서의
분류 B로 기록한다.

## 보존 규칙

- pair raw 및 warm-up raw는 삭제하지 않는다.
- 기존 Experiment 1-6 run과 분리한다.
- 이 addendum 이후 추가 실험·튜닝·MVC 비교를 자동 시작하지 않는다.
