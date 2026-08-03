# Experiment 1-19 Invalid Measurement Closure

`RUN-20260803-EXP119-BASELINE-001`은 warm-up, core, k6, drain/verification 이후 required pool collector artifact 없이 finalization 단계에서 실패했다. 따라서 pre-measurement failure가 아니며 aggregate에 포함할 수 없다.

동일 run ID 재사용과 남은 5개 run 실행은 허용하지 않는다. 정책 결정은 `NOT_RUN`, Experiment 1-19의 최종 상태는 `INVALID`다.

원본 active failure와 legacy raw는 이동·삭제·덮어쓰기 없이 보존했다. closure는 path, size, SHA-256, terminal marker, failure summary 및 run-config 계약만 읽었고 raw outcome은 열람하지 않았다.

증거 inventory와 disposition은 `backend/experiments/results/experiment-1-19/closure/`에 보존한다.
