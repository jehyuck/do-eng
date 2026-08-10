# Historical MVC VU160 Evidence

## 1. 조사 범위

이번 조사는 새 workload나 Docker 실행 없이 다음 자료를 읽어 수행했다.

- 현재 checkout의 reachable Git history (`git log --all`, path/string history)
- 현재 작업 디렉터리의 `experiment/results/**` 및 `experiment/config/**`
- `docs/*run*`, run ledger, summary 자료
- 두 후보 run의 raw `run-config.json`, `client-summary.stdout.json`, `client-results.json`, `verification-summary.json`, `mock-control.json`, `environment.json`
- 현재 SERVICE1S/SERVICE3S config와 현재 `mission-load.js` fingerprint

후보 result 디렉터리 `RUN-20260731-250` 및 `RUN-20260731-252`는 현재 Git에 추적된 history에는 없고, 로컬 raw artifact로만 확인된다.

## 2. 찾은 실행

| Run | implementation | VU evidence | 결과 요약 | validity |
|---|---|---:|---|---|
| `RUN-20260731-250` | WebFlux (`flux-corrected`) | 160 distinct users, `activeMissions=160`, `initialActiveUsers=160` | 15,492 started/completed, HTTP 200 15,492, body `true` 15,492, p95 2,488 ms, p99 2,798 ms, max in-flight 480 | `VALID` |
| `RUN-20260731-252` | MVC400 (`mvc`) | 160 distinct users, `activeMissions=160`, `initialActiveUsers=160` | 15,351 started/completed, HTTP 200 15,351, body `true` 15,351, p95 2,490 ms, p99 2,883 ms, max in-flight 480 | `VALID` |

두 run 모두 raw request에서 timeout 0, connection error 0, unfinished request 0이다. `verification-summary.json`의 `valid=true`, `measurementValidity=VALID`도 확인된다.

## 3. VU160의 의미와 “통과”의 의미

`VU160`은 raw artifact에서 160개의 distinct logical user가 사용되었고, 설정상 `activeMissions=160`, `initialActiveUsers=160`이었다는 뜻이다. 이는 요청 수가 160이라는 뜻이 아니다. 실제 요청은 reconnect-ramp 동안 반복되어 15,351~15,492건이었다.

또한 `missionCompletionCount`는 MVC400에서 5,122, WebFlux에서 5,184로 기록된다. 따라서 “160개의 mission만 성공했다”는 의미로 해석할 수 없다. 이 run에서 확인되는 좁은 의미의 통과는 모든 terminal request가 HTTP 200과 body `true`를 반환했고 측정 validity가 `VALID`였다는 것이다.

두 raw request artifact에는 각 요청의 `user`, `activationStage`, `activatedUsersAtSchedule`, `activeMissionUsersAtSchedule`가 보존되어 있다. 두 run 모두 모든 요청이 `activationStage=0`이고 `activatedUsersAtSchedule=160`이다. `initialActiveUsers=160`이므로 이 설정에서는 후속 activation stage가 생기지 않는다. 다만 historical `mission-load.js`의 정확한 timer 구현 본문은 reachable Git history나 현재 파일에서 복원되지 않아, 당시 stage-0 사용자들이 timer 내부에서 정확히 어떻게 분산되었는지는 확정하지 않는다.

## 4. Historical MVC400 조건

`RUN-20260731-252/run-config.json` 기준:

- `activeMissions=160`, `initialActiveUsers=160`, `activationStepUsers=1`
- `arrivalMode=staggered`, `loadScenario=reconnect-ramp`
- `activationIntervalMs=3000`, `intervalMs=1000`, `reconnectDelayMs=1000`
- `durationMs=105000`, `requestTimeoutMs=10000`
- AI result/status/delay: `true` / 200 / 2000 ms
- storage status/delay: 200 / 100 ms
- fixture: `image/arc.jpg`, 265,745 bytes, SHA-256 `1eeadb414471c8f89207118baad01d1a9ec7b05306df0482a79d92d2c615fa99`
- drain observation: 30 s; drain completed in 3,003 ms
- MVC service: `mvc`; MVC 400-thread override compose file SHA-256 `feacb89ffe673f25460311ca81ef06bf61ff93631e4f8de5baa97b31579c927b`
- HTTP pool 400 override was used; DB pool was 10 per the recorded experiment contract/base default, but the rendered historical value is not separately recorded in `run-config.json`.

Historical source provenance is incomplete: `environment.json` records Git HEAD `8e856468b36dcb1d7297afc05461af01d6dd6424`, but the MVC source was untracked/dirty at capture time. The historical `mission-load.js` SHA-256 was `0e4aa35004f9a2da4b39f59147d523f8a7405aac2e56380bfeef4f2284daf218`; no reachable source copy with that hash was found. Exact historical application JAR/image identity is also absent.

## 5. Comparison with current SERVICE3S/SERVICE1S

Current preregistered configs preserve the same active users, reconnect-ramp, activation settings, timeout, AI/storage delay, fixture, application resources, HTTP pool, DB pool, MVC thread setting, and JVM values. The important observed differences are:

| Variable | Historical MVC400 (`RUN-252`) | Current SERVICE3S | Current SERVICE1S |
|---|---:|---:|---:|
| `intervalMs` | 1000 | 3000 | 1000 |
| `drainObservationSeconds` | 30 | 15 | 15 |
| `mission-load.js` SHA-256 | `0e4aa35004f9a2da4b39f59147d523f8a7405aac2e56380bfeef4f2284daf218` | `f3a6eb36798a57ce408de85e5420f65273bb5c2684bc02618822c4c78095619b` | `f3a6eb36798a57ce408de85e5420f65273bb5c2684bc02618822c4c78095619b` |
| recorded runtime Git HEAD | `8e856468b36dcb1d7297afc05461af01d6dd6424` | `96c1b4cee7d695fa3c84c48ef49c8b00d8f786e9` | `441682524b3629a661a0971e9d31f3472f74c3ea` |
| compose fingerprint | historical `f858b3...` base plus historical overrides | current `a430d9...` base / `bf3d68...` runtime override | current `a430d9...` base / `bf3d68...` runtime override |

The historical interval matches SERVICE1S but not SERVICE3S. Historical drain observation is 30 s, while both current preregistered configs use 15 s. The historical workload source and application source provenance are not identical or fully reproducible from a committed source/image identity.

## 6. Final 판정

`RUN-20260731-252` confirms that a historical MVC400 VU160 execution exists and that its recorded terminal HTTP/business outcomes were successful. It does not establish a directly comparable historical baseline for the current SERVICE1S/SERVICE3S pair because the historical MVC source was not committed, the historical workload source hash is unavailable from reachable source, and exact image/JAR identity is missing. Therefore the final classification is:

`HISTORICAL_VU160_MVC_FOUND_BUT_NOT_COMPARABLE`

## 7. 아직 확인되지 않은 것

- Historical MVC application JAR SHA-256 and image ID/digest.
- The exact historical `mission-load.js` source text and line-level diff against the current file.
- A rendered historical DB pool value independent of the contract/base default.
- Whether the historical stage-0 staggering timer implementation was byte-for-byte equivalent to the current scheduler.

No performance workload, Docker startup, code change, config change, or validator change was performed for this investigation.
