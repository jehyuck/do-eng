# Experiment 1-3 — Phase A/B Source Audit

## Latest source state

The audit targets the current working-tree corrected REST path, not the 2023
implementation and not the legacy WebSocket handlers. The working tree already
contains uncommitted experiment changes; those changes are preserved and are
not treated as a clean historical commit.

## Representative request path

`POST /game/face`

`AiGameController.requestFaceAi`
→ `requestAi`
→ `Mono.zip(image, TokenComponent.jwtConfirm)`
→ `AiOutboundAdmissionGate.execute(requestDecision)`
→ `completeIfMatched`
→ `DBComponentHttp.saveData`
→ `MissionImageStorage.upload` (`HttpMissionImageStorage` by default)
→ `MissionDatabaseService.saveCompletionIfFirst`
→ R2DBC repositories / `DatabaseClient`
→ `ResponseEntity.ok("true")`.

## Static stage map

| Stage | Code | Thread/scheduler | Blocking risk | CPU risk | Composition | Shared resource |
|---|---|---|---|---|---|---|
| request body | `AiGameController.requestAi` | WebFlux request path | no blocking API found | Jackson/body aggregation not timed | `Mono<ImageRequestDto>` consumed once | inbound memory |
| token | `TokenComponent.jwtConfirm` | Reactor Netty | WebClient reactive chain | response decode only | included in `Mono.zip` | shared `doeng-external` provider |
| AI serialize/network | `requestDecision` | Reactor Netty | no `.block()`/sleep | JSON/Base64 request construction | gated by AI admission only | shared provider |
| AI response codec | `bodyToMono(AiDecisionResultDto)` | Reactor Netty | no blocking API found | JSON decode | remains in AI publisher | shared provider |
| Base64 decode | `completeIfMatched` | `Schedulers.parallel()` | `Base64` is CPU work, not I/O | explicit offload via `fromCallable` | propagated with `flatMap` | parallel scheduler |
| storage | `HttpMissionImageStorage.upload` | Reactor Netty | WebClient reactive | body encoding | returned in chain | shared provider |
| DB read/write | `MissionDatabaseService.saveCompletionIfFirst` | R2DBC | no JDBC call in this path | row mapping | returned in chain; transaction annotation present | DB pool 10 |
| response | `thenReturn(ResponseEntity.ok("true"))` | subscriber completion | no blocking API found | negligible | storage and DB complete before response | none |

## Completion-chain finding

The current REST path does not contain a detached `subscribe()` in the
`DBComponentHttp`/`MissionDatabaseService` path. Storage completion is followed
by the DB completion and only then by `thenReturn`. Therefore the requested
REST success response is composed after those publishers complete.

The older `DBComponent` used by legacy WebSocket code still contains detached
`subscribe()` calls. That is a separate path and is not evidence that the
current `/game/face` REST path has the same defect.

## WebClient/provider topology

`ExternalHttpClientConfig` creates one named `ConnectionProvider`
(`doeng-external`) and one injected `WebClient.Builder`. Token, AI and HTTP
storage clone that builder and set different base URLs. The current source does
not create a new provider per request. All three REST outbound stages therefore
share the configured provider unless a runtime profile replaces the storage
implementation. Runtime provider identity still requires runtime metric
confirmation.

## Base64/codec finding

The current REST path decodes the original request image in
`completeIfMatched` using `ImagePayloadDecoder` on `Schedulers.parallel()`.
No evidence in source alone establishes a long decode duration, event-loop
execution, or scheduler backlog. Base64 is consequently a CPU-risk candidate,
not a confirmed cause.

## Blocking audit

No `.block()`, `Thread.sleep`, JDBC call, `Future.get/join`, synchronous S3
client, or blocking semaphore was found in the current REST path. The legacy
WebSocket `DBComponent`/per-request WebClient handlers are explicitly excluded
from this path audit.

## Preliminary classification

Static evidence rules out neither runtime pool pressure nor CPU/resource
pressure. It does rule out treating the legacy detached subscription as a
confirmed `/game/face` cause. The classification remains **R5 plausible,
R1/R2/R3/R4/R6/R7 unconfirmed, R8 not yet decidable** pending stage/runtime
correlation.

## BlockHound

No BlockHound dependency or test hook was found in the current test source.
This is an audit finding, not a claim that runtime blocking is absent. A
BlockHound test may be added only if the dependency is available through the
existing JDK11/offline build gate; it is not enabled in performance runtime.
