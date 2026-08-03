# Experiment 1-20 Pool Collector Harness Readiness

새 runner는 Exp119와 별도 경로·별도 result root를 사용한다. collector output은 legacy run root를 만들지 않는 `collector-staging/{runId}`에 저장한 뒤 final `pool/` artifact로 원본 복사한다.

collector-only preflight는 fresh recreate, image/health/management endpoint 확인, 3초 collector probe, 최소 두 valid JSONL line, zero collector failures, cleanup만 수행한다. warm-up, fixture, k6, core, drain은 수행하지 않는다.

PLAN은 six run ID, 고정 순서, 150초/1초 collector contract, staging/final paths를 기록하며 실행 side effect가 없어야 한다.
