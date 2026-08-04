# Experiment 1-25 Post-Stop Capture Invocation Recovery

목표는 Exp124의 post-stop capture helper 호출 계약만 복구하는 것이다.

변경 범위:

- Experiment/Run ID를 Exp125로 분리
- production runner에서 capture parameter hashtable을 named splatting
- capture helper는 hashtable wrapper와 typed implementation을 분리
- RunId, ContainerId, ApplicationDirectory mandatory binding 검증
- temp metadata parse 후 atomic publish 유지

Frozen image, Compose 7개, policy, workload, resource, collector, preflight, terminal contract, crossover 순서는 유지한다.

이번 단계에서는 warm-up, k6, core, 성능 분석을 수행하지 않는다.

