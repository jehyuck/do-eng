# Exp133-R 관측 계약 보정

## Evidence 우선순위

Primary evidence는 rendered compose, runtime container environment, application image provenance, Admission before/during/after, request outcome raw, application/container resource raw, load-stop, drain, consistency, application verification summary다.

Reactor Netty pool series와 collector summary/failure log는 secondary evidence다. 따라서 collector가 일부 실패했더라도 primary evidence와 application lifecycle이 보존된 경우 request·latency·failure·resource 결과를 `VALID_PRIMARY_POOL_METRICS_LIMITED`로 보존한다. Pool metric 기반 결론은 내리지 않는다.

## Provenance

각 실행은 `exp133-run-config.json`에 planned, rendered, runtime의 `sharedPoolMaxConnections`를 별도 기록한다. 세 값이 일치하지 않으면 validator는 실패한다.

## Collector lifecycle

Collector는 explicit stop signal을 우선 사용하고, bounded maximum duration을 보조 종료 조건으로 사용한다. maximum duration에 먼저 도달하면 `STOP_SIGNAL_MISSED`를 기록한다. collector failure row는 삭제하거나 성공 sample로 대체하지 않으며, application/load-generator lifecycle과 독립적으로 보존한다.
