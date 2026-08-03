# Experiment 1-20 Fresh-First Clean A/B Plan

Experiment 1-19는 required pool collector artifact 누락으로 INVALID 종료했다. Exp120은 결과를 열람하지 않은 상태에서 동일한 application/mock image, policy, workload와 실행 순서를 사용한다.

고정 순서: BASELINE-001, REMEDIATION-001, BASELINE-002, REMEDIATION-002, BASELINE-003, REMEDIATION-003.

실행 시 `-RunDate YYYYMMDD`로 6개 run ID를 고정한다. BASELINE은 FIFO/0/0, REMEDIATION은 LIFO/3000/1000이며, 이것만 arm 간 허용 차이다.

VU200, 105초, 1초 interval/reconnect, AI 2000ms, storage 100ms, timeout 10초, drain 30초, app 2CPU/3GiB, pool400/pending800, DB pool10, admission320은 고정한다.

pool collector는 warm-up 뒤 core 직전에 시작해 150초/1초로 staging 경로에 기록한다. final artifact는 JSONL·summary 모두 존재하고, non-empty, valid, `summary.failures=0`이어야 한다. 동일 run ID rerun·추가 run·결과 기반 조건 변경은 금지한다. Decision 기준은 Exp119 사전등록 기준을 변경 없이 승계하며 `NOT_RUN` 상태로 시작한다.
# 2026-08-03 coverage-gate addendum

Core execution is permitted only after the pool collector has written a first valid JSONL sample within 10 seconds. Each future core run must preserve `pool/collector-coverage.json`; it is a validity artifact, not a performance outcome. The frozen workload, resources, images, policy conditions, six-run order, and 150-second / one-second collector contract are unchanged.
