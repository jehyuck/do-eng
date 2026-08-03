# Experiment 1-19 — Fresh-First A/B Harness 및 Provenance Dry-run 계획

작성일: 2026-08-03
상태: 구현 및 preflight 전 사전 계획

## 질문

6개 core A/B 실행 전에 baseline과 remediation의 rendered Compose·runtime configuration·source/image·fixture/auth/reset·collector/aggregator 경로가 lifecycle 세 변수만 제외하고 같은지 검증할 수 있는가?

## 기준

- implementation commit: `270349fa7937eb4486087d34184461ae6aaab10a`
- baseline: FIFO / 0ms / 0ms
- remediation: LIFO / 3,000ms / 1,000ms
- Experiment 1-13의 base Compose, capture sidecar, pool collector, DB/container monitor, load/drain 계약을 재사용한다.

## 허용 변경

- Experiment 1-19 Compose overlay
- condition selector가 있는 preflight-only wrapper
- 기존 Experiment 1-13 config diff/aggregator를 기반으로 한 최소 확장
- preflight artifact와 docs/171~172, run ledger

## 고정 조건

VU 200, duration 105초, 1초 frame/reconnect, AI 2,000ms, storage 100ms, timeout 10초, drain 30초, app 2 CPU/3GiB, outbound pool 400/800, DB pool 10, admission 320, fixture/auth/reset, Java/Node, collector sampling, health gate, request contract를 변경하지 않는다.

## Preflight 절차

각 condition에서 다음만 수행한다.

1. implementation commit Git archive로 application image를 한 번 build하고 image ID/digest를 기록한다.
2. condition 환경변수로 masked rendered Compose를 만들고 lifecycle 세 변수 외 diff를 검증한다.
3. fresh recreate 후 app/mock/DB health, mock idle, DB reset command, mock reset command, fixture/auth path, collector executable을 확인한다.
4. container environment와 Java 11 property-binding test를 runtime binding 근거로 저장한다.
5. core load command을 artifact에 구성하되 실행 직전에 hard stop한다.
6. artifact를 검증하고 container cleanup을 수행한다.

## Runtime proof 경계

현재 endpoint는 pool mode/metric을 노출하지만 leasing/max-idle/eviction property 전체를 노출하지 않는다. 이번 범위에서 production endpoint를 확장하지 않고, container environment와 `ExternalServicePropertiesTest`의 Java 11 binding/validation evidence를 사용한다. 따라서 결과 문서에 runtime 값의 출처와 이 한계를 명시한다.

## Aggregator 준비

6 core artifact가 존재할 때만 실행되는 aggregator schema를 준비한다. validity, provenance, primary reliability, guardrail, 사전등록 decision enum을 검증하되, 이번 단계에서는 `NOT_RUN`만 기록하고 가상 결과나 decision을 만들지 않는다.

## 성공·실패

모든 deterministic gate, 동일 image, controlled rendered/runtime diff, 두 preflight, reset/fixture/auth/health, collector/aggregator schema가 통과하고 core request가 0이면 `READY_FOR_SIX_CORE_RUNS`다. 하나라도 부족하면 `HARNESS_INVALID` 또는 `INVALID`으로 기록하고 즉시 조건을 변경하지 않는다.

## Hard stop

BASELINE-001/REMEDIATION-001을 포함한 core workload, 추가 값 탐색, MVC, 정책 채택/rollback은 수행하지 않는다.
