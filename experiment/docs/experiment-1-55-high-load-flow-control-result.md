# Exp155 High-Load Flow-Control Comparison 결과

## 1. 실행 기준

- 실험: Exp155 High-Load Flow-Control Comparison
- 하중: 200 active missions, staggered, 1초 간격, 30초
- AI mock: 2,000ms / 200, Storage mock: 100ms / 200
- 애플리케이션 자원: 2 CPU / 3 GiB, JVM Xms512m/Xmx2g/G1GC
- DB pool: 10, client timeout: 15초, 동일 fixture SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- Provider: ISOLATED, TOKEN 100/160, AI 400/640, STORAGE 100/160, pending acquire timeout 10초
- Production Java 변경: 없음

CONTROL/GATE는 source `507e075016728daeaab75a51e7172577efe4c5ce`, SINK는 source `cf5b36ad38928d55eab131d1328dc85ccff0ad3b`를 사용했다. 실행 중 frozen application/mock image를 재빌드하지 않았다.

## 2. 파일럿 게이트

| 셀 | 파일럿 | 결과 | 관찰 |
|---|---|---|---|
| CONTROL | CONTROL-PILOT-007 | VALID | 3,585 completed, 성공 57, maxInFlight 1,345, drain 18,011ms |
| GATE | GATE-PILOT-001 | VALID | 3,800 completed, 성공 190, drain 11,014ms |
| SINK | SINK-PILOT-001 | VALID | 4,102 completed, 성공 96, drain 2,042ms |

초기 CONTROL 파일럿의 설정 계약 누락과 이전 실행의 포트 잔여는 성능 결과가 아닌 하네스 사전실패로 보존했다. 오버레이에 SHARED 기준 예산(600/960)을 명시한 뒤 새 파일럿에서 정상화했다.

## 3. Core validity

사전등록 순서 `CONTROL-1 → GATE-1 → SINK-1 → SINK-2 → GATE-2 → CONTROL-2 → CONTROL-3 → SINK-3 → GATE-3`로 9개를 실행했다. 9개 모두 `valid=true`, load result·warm-up·collector·cleanup artifact를 보유한다.

## 4. 요청 결과 원본 요약

| 셀 | run | completed | HTTP 200 | HTTP 500 | HTTP 503 | timeout | connection error | p95 ms | max in-flight |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CONTROL | 1 | 3,849 | 110 | 508 | 0 | 2,043 | 1,188 | 14,871 | 1,687 |
| CONTROL | 2 | 3,869 | 33 | 614 | 0 | 2,757 | 465 | 14,980 | 1,864 |
| CONTROL | 3 | 3,880 | 4 | 465 | 0 | 2,452 | 959 | 14,790 | 1,685 |
| GATE | 1 | 3,730 | 282 | 139 | 1,120 | 957 | 1,232 | 14,477 | 1,067 |
| GATE | 2 | 3,400 | 114 | 156 | 705 | 1,080 | 1,345 | 14,349 | 1,061 |
| GATE | 3 | 3,902 | 164 | 187 | 1,210 | 927 | 1,414 | 13,785 | 1,081 |
| SINK | 1 | 3,750 | 203 | 7 | 493 | 1,042 | 1,532 | 14,963 | 1,204 |
| SINK | 2 | 3,930 | 51 | 11 | 515 | 1,391 | 1,194 | 14,850 | 1,537 |
| SINK | 3 | 5,357 | 125 | 95 | 1,286 | 824 | 0 | 14,696 | 2,544 |

### 3회 중앙값

| 셀 | success rate | successful RPS | p50 | p95 | p99 |
|---|---:|---:|---:|---:|---:|
| CONTROL | 0.85% | 128.97 | 12,550 | 14,871 | 15,456 |
| GATE | 4.20% | 124.33 | 6,001 | 14,349 | 15,158 |
| SINK | 2.33% | 131.00 | 12,040 | 14,850 | 15,417 |

중앙값만 보면 SINK의 p95는 CONTROL과 사실상 같은 수준이며, successful RPS 차이는 작다. 개별 run 방향은 일관되지 않았다.

## 5. Provider·stage·drain 관찰

- 모든 load-stop 최종 pool snapshot에서 `pending.connections=0`이었다.
- provider final snapshot은 TOKEN/AI/STORAGE별 active/idle/total/max/pending을 숫자로 보존했다.
- continuous JSONL의 provider metric 배열은 문자열화된 행도 포함하여 pending peak와 acquire wait의 시계열 정량 집계는 `NOT AVAILABLE`이다. 따라서 pending 감소·acquire timeout 감소를 반복적으로 주장하지 않는다.
- stage-final의 대표 maxInFlight 범위: CONTROL AI 347–562, GATE AI 297–353, SINK AI 386–873. TOKEN과 STORAGE도 run 간 편차가 컸다.
- SINK queue depth/queue-wait 및 `result_emission_failed`의 단계별 수치는 현재 artifact에서 `NOT AVAILABLE`이다. mock downstream in-flight는 모든 core에서 drain 후 0으로 수렴했다.
- drain time-to-zero(ms): CONTROL 0/2,035/21,009, GATE 13,009/14,008/13,016, SINK 10,008/12,064/11,259. 모든 SINK run은 30초 drain 완료 및 최종 AI/Storage 0이었다.

## 6. 자원 관찰

container stats에서 application의 관찰 최대치는 대략 CPU 199–236%와 memory 508–1,009 MiB 범위였다(2 CPU/3 GiB 제한 내). GC pause와 thread 상세 시계열은 이번 계약의 필수 수집값이 아니어서 `NOT AVAILABLE`이다. restart/OOM은 9개 core에서 관찰되지 않았다.

## 7. 최종 판정

`INCONCLUSIVE`

근거:

1. SINK에서 HTTP 500과 client timeout이 CONTROL보다 낮은 방향은 보이지만, successful RPS·p95·connection error는 반복적으로 같은 방향이 아니다.
2. SINK-3의 completed/attempt 규모가 다른 run보다 커 maxInFlight가 2,544까지 올라 run 간 변동성이 크다.
3. provider pending peak/acquire wait의 직접 시계열과 Sink queue/wait 시계열이 현재 artifact에서 정량적으로 복원되지 않아, SINK의 안정성 개선을 인과적으로 확정할 수 없다.

따라서 이번 결과로 `SINK_RECOVERY_BENEFIT`, `SINK_STABILITY_ONLY`, 또는 production 채택을 확정하지 않는다. 추가 성능 튜닝도 시작하지 않는다.

## 8. 주장 범위

현재 직접 뒷받침되는 사실은 다음으로 제한한다.

- 동일한 synthetic high-load 조건에서 CONTROL, admission GATE, 기존 Sink Dispatcher 경로를 각각 3회 실행했다.
- 9개 core run은 하네스 validity 기준을 통과했다.
- 세 셀 모두 높은 오류·timeout·tail latency가 관찰됐고, SINK의 일부 오류 지표가 낮은 방향을 보였지만 반복 가능한 종합 우위는 확인되지 않았다.

WebFlux 일반 우위, Sink Dispatcher의 운영 안정성·처리량 개선, 최적 concurrency/queue는 주장하지 않는다.

## 9. 산출물

- Aggregate: `experiment/results/experiment-1-55/aggregate-summary.json`
- Run raw: `experiment/results/experiment-1-55/<RUN-ID>/`
- Plan: `experiment/docs/experiment-1-55-high-load-flow-control-plan.md`

추가 부하 실행과 설정 튜닝은 본 결과만으로 승인되지 않는다.
