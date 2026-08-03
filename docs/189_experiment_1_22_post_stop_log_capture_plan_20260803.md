# Experiment 1-22 Post-Stop Log Capture Plan

Exp121의 policy, workload, frozen images, collector 조건은 유지한다. 변경은 Experiment ID/run ID/result root와 측정 종료 후 application container stop, stopped-state 확인, post-stop log capture, 30초 timeout 및 관련 artifact/timeline뿐이다.

고정 순서는 core 완료 → collector coverage → application stop → stopped/exited 확인 → `docker logs --timestamps` snapshot → metadata 검증 → artifact copy → structural/committed validation → terminal marker → cleanup이다.

Timeout은 `APPLICATION_LOG_CAPTURE_TIMEOUT`으로 분리하고 partial stdout/stderr를 보존한다. 이 단계에서는 warm-up, k6, core, drain, 성능 분석을 수행하지 않는다.
