# Experiment 1-9 concurrency limit 사전 등록

## 선택값

`configured concurrency limit = 320`

## 선택 시점

OBSERVE 대체 run `RUN-20260802-EXP19-OBSERVE-002`가 measurement validity `VALID`로 끝난 뒤, ENFORCE core를 시작하기 전에 등록한다.

## 근거

1. 동일 VU200/AI 2 s/storage 100 ms/SHARED pool400/pending800 조건의 기존 FULL_PATH320 valid runs에서 gate는 320에서 permit leak 없이 동작했고 accepted p95는 8,552~9,275 ms였다.
2. 새 OBSERVE run에서는 limit을 강제하지 않았을 때 admission max in-flight 1,576, `wouldReject=20,346`, HTTP 200 11,022(105 s 기준 successful goodput 104.97 RPS), accepted p95 9,266 ms가 관찰됐다.
3. 같은 OBSERVE raw에서 shared pool active가 400에 도달하고 pending이 800 부근/초과로 유지되며 HTTP 500 8,049와 client timeout 1,595가 발생했다. 따라서 무제한 관찰값 1,576을 그대로 limit으로 쓰면 pool collapse를 허용한다.
4. 320은 기존 FULL_PATH 관찰·강제 계약에서 이미 사용한 값이라 새로운 sweep 없이 비교 가능하며, 현재 실험의 목적(전체 path가 pool budget을 잠식하지 않도록 fast-fail)을 직접 검증할 수 있다.

## 판정 규칙

320은 production optimum으로 주장하지 않는다. ENFORCE 결과에서 uncontrolled 500/connection error/pool acquire error가 0이고, permit leak 0·drain 완료·successful goodput과 accepted latency가 OBSERVE의 sustainable baseline을 충족하는지로만 평가한다.

## 변경 금지

이 문서 등록 후 limit sweep, pool 증설/분리, timeout/AI delay/VU/resource 변경, queue·retry·adaptive concurrency 추가를 하지 않는다. 실패해도 이 실험 안에서 다른 limit을 자동 선택하지 않는다.
