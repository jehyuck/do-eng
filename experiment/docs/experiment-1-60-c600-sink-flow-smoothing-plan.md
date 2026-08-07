# Exp160 C600 Sink Flow-Smoothing Revalidation Plan

## 질문

Exp158의 Admission OFF control과 동일한 provider·workload에서 bounded Sink dispatcher(TOKEN/AI/STORAGE=100/400/100, queue=300/1200/300)가 provider pending과 시간 의존적 backlog를 완화하면서 accepted HTTP200 completion을 유지 또는 개선하는지 확인한다.

## 고정 조건

- provider: TOKEN 100/160, AI 600/960, STORAGE 100/160, ISOLATED
- Admission OFF, Sink ON
- Sink logical concurrency: TOKEN 100, AI 400, STORAGE 100
- queue capacity: TOKEN 300, AI 1200, STORAGE 300
- VU/active missions 200, staggered, interval 1s, duration 30s, drain 15s
- AI 2s, storage 100ms, timeout 15s, pending acquire 10s
- app 2CPU/3GiB, JVM Xms512m/Xmx2g/G1GC, DB pool 10, same fixture/mock/source contract

## Control

Exp158 `C600-100-R1`을 동일 fingerprint 확인 후 재사용하며 OFF control 부하는 다시 실행하지 않는다. Sink implementation 자체는 현재 source에 존재하므로, control reuse는 request/provider/workload 조건이 동일한지 기준으로 판단한다.

## 관측과 판정

accepted HTTP200/sec를 primary로 두고 HTTP200 latency, HTTP500/timeout/connection error, dispatcher queue depth·active, cumulative enqueued/dequeued/completed/failed/rejected/cancelled, queue wait, deadline phase, provider active/pending, CPU/memory, drain을 수집한다. Queue가 bounded 상태로 유지되고 provider pressure 또는 completion collapse가 완화되는지 별도로 판정한다. 단일 run으로 최적 concurrency·queue나 일반 운영 결론을 주장하지 않는다.

## 실행

새 성능 run은 `SINK-C400-Q3` 한 번만 수행한다. instrumentation smoke가 실패하면 본 실행을 시작하지 않고 중단한다. 결과가 valid이면 Exp160을 종료하며 추가 grid/confirmation은 실행하지 않는다.
