# Experiment 1-23 Core-Bound Collector Plan

Exp122의 고정 150초 collector를 폐기하고 core lifecycle에 bound된 collector를 사용한다.

- mode: `CORE_BOUND_STOP_SIGNAL`
- interval: 1000ms
- readiness timeout: 10s
- post-core sample timeout: 10s
- graceful stop timeout: 10s
- max duration safety ceiling: 300s
- core 완료 후 covering sample 확인 → atomic stop signal → graceful exit
- policy/workload/images/collector interval/container stop/log capture/crossover는 Exp122와 동일
- controlled diff는 collector lifecycle과 관련 Evidence뿐이다.

Run IDs:
`RUN-{RunDate}-EXP123-{BASELINE|REMEDIATION}-{001|002|003}`
