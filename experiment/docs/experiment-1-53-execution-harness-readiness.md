# Exp153 Execution Harness Readiness

## 구현 범위

`run-exp153-cell.ps1`에 Plan/Smoke/Execute 단일 진입점을 추가했다. 각 실행은 run-manifest, source/fixture fingerprint, controlled diff, load command/exit, metric JSONL, resource JSONL, validity, accounting, cleanup artifact를 run 디렉터리에 남긴다.

Cell A는 dispatcher metrics를 `applicable=false`로 기록하고, Cell B는 dispatcher 경로의 수집 대상임을 명시한다. Plan 모드는 Docker와 load process를 시작하지 않는다.

## 검증 명령

```powershell
.\experiment\scripts\run-exp153-cell.ps1 -Cell A -RunId A1 -Mode Plan -ExpectedCommit <HEAD>
.\experiment\scripts\run-exp153-cell.ps1 -Cell B -RunId B1 -Mode Plan -ExpectedCommit <HEAD>
```

Smoke/Execute는 동일한 진입점에서 fresh compose recreate, health, warm-up, collector, 기존 `mission-load.js`, drain 대기, artifact 작성, cleanup 순서를 사용한다. 본 문서 작성 단계에서는 본 A/B 부하를 실행하지 않는다.

## 제한

실제 Cell A source checkout/build는 실행 시점에 별도 clean worktree 또는 archive context가 필요하다. 현재 작업 tree를 A source처럼 재사용하지 않도록 runner가 source fingerprint를 기록한다. Production Java, workload, dispatcher 설정은 변경하지 않았다.
