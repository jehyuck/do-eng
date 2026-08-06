# Exp152·153 Canonical Result

## 1. Scope

이 문서는 Exp152 Sink Dispatcher 구현 사실과 Exp153 Controlled A/B의 실행 종료 상태를 고정한다. 새로운 실험, 성능 분석, 설정 변경은 포함하지 않는다.

기준 브랜치: `experiment/exp152-sink-dispatcher`
기준 시작 HEAD: `468005be13fee3ca8786d815b7a02b2720e14d68`

## 2. Exp152 Implementation

현재 소스에서 확인된 구현 사실은 다음과 같다.

- TOKEN, AI, STORAGE 단계별로 독립 `SinkDispatcher`를 사용한다.
- 각 dispatcher는 bounded `ArrayBlockingQueue`, 단일 장수 consumer, 단계별 concurrency 제한을 가진다.
- enqueue 전·실행 전 deadline을 확인하고 남은 global deadline을 실행에 적용한다.
- 취소된 queued work는 dequeue 시 건너뛴다.
- 개별 작업 오류를 consumer 전체 종료와 분리한다.
- queue-full과 deadline 만료를 서로 다른 예외 경로로 구분한다.
- 단계 순서는 TOKEN → AI → image decode → STORAGE → DB로 유지된다.
- 기존 Admission Gate와 isolated Reactor Netty provider, DB 접근은 제거하거나 재설계하지 않았다.
- dispatcher metrics는 queue depth, active, queue wait, event counter를 단계 tag와 함께 노출한다.
- request identity(`X-Experiment-Request-Id`, `X-Experiment-Run-Id`, `X-Mission-Run-Id`)는 dispatcher 경계를 지나 downstream 요청에 전달된다.

주요 근거는 `backend/doEngGameFlux/src/main/java/com/example/doenggameflux/dispatcher/`, 각 단계 dispatcher 구현체, `RequestIdentity`, `AiGameController`, 그리고 Exp152 구현·검증 문서다.

## 3. Verified Runtime Behavior

기존 Exp152 기록에 따라 다음은 검증된 사실로 보존한다.

- Gradle test: PASS
- bootJar: PASS
- Spring Context: PASS
- 정상 runtime smoke: PASS
- TOKEN → AI → STORAGE → DB 정상 요청 경로: PASS
- queue-full 응답 매핑 HTTP 503: PASS
- global deadline 응답 매핑 HTTP 504: PASS
- 세 상관관계 헤더 전달: PASS

이는 구현·단위·기능 smoke 검증 결과이며, 고부하 성능 결과가 아니다.

## 4. Exp153 Controlled A/B Status

- Controlled A/B: NOT EXECUTED
- Valid baseline runs: 0
- Valid sink runs: 0
- Aggregate: NOT AVAILABLE
- Performance comparison: NOT AVAILABLE
- Final classification: `ENVIRONMENT_BLOCKED`

실행 차단 이력은 execution runner 부재, source isolation 보강, pool reference contract 정합화, PowerShell harness 조건식 오류, 호스트 Node.js 실행 파일 부재, 허용된 smoke 재시도 소진이다. A/B가 실행되지 않았으므로 Exp153은 Sink Dispatcher의 효과·회귀·최적값을 판정하지 않는다.

## 5. Confirmed Facts

- Exp152의 bounded stage-isolated dispatcher 구조가 소스에 존재한다.
- 단계별 concurrency와 queue capacity 설정이 코드와 문서에 정의되어 있다.
- global deadline, cancellation skip, 오류 격리, queue-full/deadline 예외 경로가 구현되어 있다.
- 관련 테스트와 정상·오류 smoke 검증 기록이 존재한다.
- Exp153의 Controlled A/B 측정은 시작되지 않았다.

## 6. Claim-Evidence Matrix

| Claim | Evidence | Status | Usage |
|---|---|---|---|
| 단계별 bounded Dispatcher 구현 | dispatcher source 및 Exp152 문서 | PASS | PORTFOLIO_ALLOWED |
| TOKEN/AI/STORAGE concurrency·queue 격리 | 각 dispatcher와 `DispatcherSpec` | PASS | PORTFOLIO_ALLOWED |
| global deadline 전파 | `MissionExecutionContext`, dispatcher deadline 경로 | PASS | PORTFOLIO_ALLOWED |
| queued cancellation skip | `DispatchWork`, dispatcher 테스트 | PASS | PORTFOLIO_ALLOWED |
| 개별 작업 오류 격리 | `AbstractSinkDispatcher` 오류 처리 및 테스트 | PASS | PORTFOLIO_ALLOWED |
| queue-full → HTTP 503 | 예외 handler 테스트·기능 smoke | PASS | PORTFOLIO_ALLOWED |
| deadline → HTTP 504 | 예외 handler 테스트·기능 smoke | PASS | PORTFOLIO_ALLOWED |
| 정상 전체 요청 경로 | Spring Context 및 정상 smoke 기록 | PASS | PORTFOLIO_ALLOWED |
| 처리량 개선 | Exp153 A/B 미실행 | NOT AVAILABLE | PROHIBITED |
| provider pending 감소 | 비교 실행 없음 | NOT AVAILABLE | PROHIBITED |
| timeout 감소 | 비교 실행 없음 | NOT AVAILABLE | PROHIBITED |
| 기존 직접 reactive chain 대비 우수성 | 비교 실행 없음 | NOT AVAILABLE | PROHIBITED |
| 최적 concurrency·queue 도출 | 사전 통계·최적화 실험 없음 | NOT AVAILABLE | PROHIBITED |

## 7. Allowed Claims

- 단계별 bounded Sink Dispatcher를 구현했다.
- TOKEN, AI, STORAGE의 concurrency와 queue를 분리했다.
- 요청 전체 deadline을 단계 경계에서 전파했다.
- queued cancellation과 개별 작업 오류를 격리했다.
- queue full과 deadline 만료를 HTTP 503과 504로 구분했다.
- Spring Context와 정상 요청 경로를 검증했다.

## 8. Prohibited Claims

다음 주장은 현재 자료로 할 수 없다.

- 처리량 또는 성공 RPS가 개선됐다.
- provider pending이나 timeout이 감소했다.
- 기존 직접 reactive chain보다 우수하다.
- backpressure 문제가 해결됐다.
- 운영 안정성이 개선됐다.
- 최적 concurrency 또는 queue capacity를 찾았다.

## 9. Interview Explanation

1. 어떤 문제를 해결하려 했는가?
외부 TOKEN·AI·STORAGE 작업이 각자의 대기와 실행 자원을 공유하면서 요청 전체 deadline과 오류 경계를 분리하기 어려운 문제를 다루려 했다.

2. 어떤 구조를 구현했는가?
각 단계에 bounded queue와 concurrency 제한을 가진 장수 Sink consumer를 두고, 요청의 global deadline과 correlation identity를 단계 전체에 전달했다.

3. 무엇을 검증했는가?
Gradle test, bootJar, Spring Context, 정상 요청 경로, queue-full 503, deadline 504, correlation header 전달을 검증했다.

4. 무엇은 주장하지 않는가?
Controlled A/B 부하가 실행되지 않았기 때문에 처리량, latency, provider pending, timeout 개선이나 기존 체인 대비 우수성은 주장하지 않는다.

## 10. Future Experiment Boundary

Exp153은 이 문서에서 종료한다. 추가 성능 실험은 별도 실험 번호와 별도 사전등록으로 시작해야 하며, 현재 포트폴리오 범위에서는 재개하지 않는다. 향후 실험이 시작되기 전까지 Exp153의 성능 결론을 보완하거나 재해석하지 않는다.

## 11. Canonical State

```text
EXP152_IMPLEMENTATION:
VALIDATED

EXP152_RUNTIME_BEHAVIOR:
VALIDATED

EXP153_CONTROLLED_AB:
NOT EXECUTED

EXP153_VALID_A_RUNS:
0

EXP153_VALID_B_RUNS:
0

EXP153_PERFORMANCE_CLAIM:
NOT AVAILABLE

EXP153_FINAL_CLASSIFICATION:
ENVIRONMENT_BLOCKED

PORTFOLIO_USAGE:
NON_PERFORMANCE_CLAIMS_ONLY
```
