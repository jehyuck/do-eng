# Experiment 1-24 Artifact Path Preflight Plan

목표는 Exp123의 artifact finalization 경로 오류를 사전에 검출하는 것이다. Exp123 raw와 frozen 조건은 변경하지 않는다.

## Controlled diff

- experiment/run ID 및 result root
- artifact directory preflight
- container-stop metadata parent 생성과 atomic write
- post-stop capture application directory 생성과 metadata atomic write
- preflight artifact 및 검증

정책, workload, resource, frozen image, Compose, collector, timeout, crossover 순서는 유지한다.

## Preflight contract

각 run root에 application, pool, database, container, mock, drain, provenance를 생성하고 각 디렉터리에 임시 write/delete probe를 수행한다. 모든 canonical path가 run root 내부인지 확인한다. 결과는 provenance/artifact-path-preflight.json에 기록하며 성공 상태는 ARTIFACT_PATH_PREFLIGHT_PASSED이다.

## Fixture

X1~X9 fixture, BASELINE/REMEDIATION production-path probe, individual/six-core PLAN만 수행한다. warm-up, k6, core, performance analysis, policy decision은 이 단계에서 수행하지 않는다.

