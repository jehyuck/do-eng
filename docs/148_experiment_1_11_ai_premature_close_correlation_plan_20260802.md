# Experiment 1-11 AI Premature Close Correlation 계획

## 질문

Experiment 1-10에서 request ID가 누락됐던 AI `PrematureCloseException`을 client → inbound → AI stage → mock lifecycle 단위로 직접 연결할 수 있는가?

## 구현 경로

`Inbound header → Reactor Context → AI stage diagnostic → AI WebClient correlation header → AI mock lifecycle → request ID join artifact`

Reactor Netty callback은 connection-level 보조 증거로만 사용하며 nullable request 객체를 request identity로 사용하지 않는다.

## 고정 조건

- ENFORCE full-path admission 320
- shared pool max 400, pending max 800
- VU200, AI 2초, storage 100ms, frame/reconnect 1초
- duration 105초, client timeout 10초
- app 2 CPU/3 GiB, DB pool 10
- 동일 fixture/auth/DB/storage contract
- retry, timeout, scheduler, body, response mapping, TOKEN/STORAGE 호출 유지

## 관측 변경

- 세 identity를 Reactor Context에 저장
- StageObservation의 기존 counter와 publisher semantics를 유지하며 request-scoped lifecycle event 추가
- AI WebClient 요청에만 Context identity header 전달
- mock AI endpoint에 request/response/socket lifecycle event 추가
- client/inbound/stage/mock/connection artifact를 request ID로 join

## 사전 테스트

1. Context propagation
2. admission rejection 시 AI/mock 미호출
3. 정상 AI response lifecycle
4. response 전 forced close와 PrematureClose/HTTP500 연결
5. client cancellation 시간 순서
6. diagnostic off 기존 동작 유지

모든 테스트가 통과한 뒤에만 core를 실행한다.

## 실행

- CLEAN core 3회
- 각 run 전 app/mock recreate, health UP, mock in-flight 0, warm-up, artifact writable 확인
- source commit과 Compose hash 고정
- 세 번 종료 후 추가 실행하지 않음

## 산출물

각 run에 `correlation-join.jsonl`, `correlation-summary.json`, `connection-events.jsonl`, `correlation-provenance.json`을 보존한다. 최종 결과는 별도 Experiment 1-11 결과 문서에 기록한다.
