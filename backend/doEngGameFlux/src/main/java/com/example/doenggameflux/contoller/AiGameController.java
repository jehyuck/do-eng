package com.example.doenggameflux.contoller;

import com.example.doenggameflux.component.AiDispatchRequest;
import com.example.doenggameflux.component.AiDispatcher;
import com.example.doenggameflux.component.AiOutboundAdmissionGate;
import com.example.doenggameflux.component.DBComponentHttp;
import com.example.doenggameflux.component.DiagnosticErrorLogger;
import com.example.doenggameflux.component.OutboundStage;
import com.example.doenggameflux.component.RequestIdentity;
import com.example.doenggameflux.component.StageObservation;
import com.example.doenggameflux.component.TokenDispatcher;
import com.example.doenggameflux.dispatcher.MissionExecutionContext;
import com.example.doenggameflux.dto.request.ImageRequestDto;
import com.example.doenggameflux.dto.response.AiDecisionResultDto;
import com.example.doenggameflux.util.ImagePayloadDecoder;
import java.time.Duration;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping
public class AiGameController {

    private final DBComponentHttp dbComponent;
    private final TokenDispatcher tokenDispatcher;
    private final AiDispatcher aiDispatcher;
    private final DiagnosticErrorLogger diagnosticErrorLogger;
    private final AiOutboundAdmissionGate aiAdmissionGate;
    private final StageObservation stageObservation;
    private final Duration globalDeadline;

    public AiGameController(
            DBComponentHttp dbComponent,
            TokenDispatcher tokenDispatcher,
            AiDispatcher aiDispatcher,
            DiagnosticErrorLogger diagnosticErrorLogger,
            AiOutboundAdmissionGate aiAdmissionGate,
            StageObservation stageObservation,
            @Value("${doeng.dispatcher.global-deadline:10s}") Duration globalDeadline) {
        this.dbComponent = dbComponent;
        this.tokenDispatcher = tokenDispatcher;
        this.aiDispatcher = aiDispatcher;
        this.diagnosticErrorLogger = diagnosticErrorLogger;
        this.aiAdmissionGate = aiAdmissionGate;
        this.stageObservation = stageObservation;
        this.globalDeadline = globalDeadline;
    }

    @GetMapping("/test")
    public Mono<String> test() {
        return Mono.just("안녕하세요");
    }

    @PostMapping("/game/face")
    public Mono<ResponseEntity<String>> requestFaceAi(
            @RequestBody Mono<ImageRequestDto> image,
            @RequestParam("answer") String answer,
            @RequestParam("sceneId") long sceneId,
            ServerWebExchange exchange) {
        return requestAi(image, answer, sceneId, exchange, "/face");
    }

    @PostMapping("/game/object")
    public Mono<ResponseEntity<String>> requestObjectAi(
            @RequestBody Mono<ImageRequestDto> image,
            @RequestParam("answer") String answer,
            @RequestParam("sceneId") long sceneId,
            ServerWebExchange exchange) {
        return requestAi(image, answer, sceneId, exchange, "/object");
    }

    @PostMapping("/game/doodle")
    public Mono<ResponseEntity<String>> requestDoodleAi(
            @RequestBody Mono<ImageRequestDto> image,
            @RequestParam("answer") String answer,
            @RequestParam("sceneId") long sceneId,
            ServerWebExchange exchange) {
        return requestAi(image, answer, sceneId, exchange, "/doodle");
    }

    private Mono<ResponseEntity<String>> requestAi(
            Mono<ImageRequestDto> image,
            String answer,
            long sceneId,
            ServerWebExchange exchange,
            String aiPath) {
        String authorization = exchange.getRequest()
                .getHeaders()
                .getFirst("Authorization");
        String missionRunId = normalizeMissionRunId(exchange.getRequest()
                .getHeaders()
                .getFirst("X-Mission-Run-Id"));

        if (authorization == null) {
            return Mono.just(ResponseEntity
                    .status(HttpStatus.UNAUTHORIZED)
                    .body("JWT token Not Found"));
        }
        if (missionRunId == null) {
            return Mono.just(ResponseEntity.badRequest()
                    .body("Invalid X-Mission-Run-Id"));
        }

        MissionExecutionContext executionContext =
                MissionExecutionContext.start(missionRunId, globalDeadline);

        Mono<ResponseEntity<String>> pipeline = Mono.deferContextual(contextView -> {
            RequestIdentity requestIdentity = RequestIdentity.from(contextView);
            return Mono.zip(
                            image,
                            stageObservation.observe("TOKEN", aiAdmissionGate.executeStage(
                                    OutboundStage.TOKEN,
                                    () -> tokenDispatcher.dispatch(
                                            executionContext,
                                            authorization))))
                    .flatMap(tuple -> stageObservation.observe("AI", aiAdmissionGate.executeStage(
                            OutboundStage.AI,
                            () -> aiDispatcher.dispatch(
                                    executionContext,
                                    new AiDispatchRequest(
                                            tuple.getT1(),
                                            answer,
                                            aiPath,
                                            requestIdentity))))
                            .flatMap(decision -> completeIfMatched(
                                    executionContext,
                                    decision,
                                    tuple.getT1().getImage(),
                                    sceneId,
                                    tuple.getT2(),
                                    missionRunId)));
        });

        return (aiAdmissionGate.isPerOutboundCall() ? pipeline : aiAdmissionGate.execute(() -> pipeline))
                .doOnError(error -> diagnosticErrorLogger.log(missionRunId, error))
                .onErrorResume(
                        WebClientResponseException.class,
                        error -> Mono.just(ResponseEntity
                                .status(error.getStatusCode())
                                .body(error.getResponseBodyAsString())));
    }

    private Mono<ResponseEntity<String>> completeIfMatched(
            MissionExecutionContext executionContext,
            AiDecisionResultDto decision,
            String originalImage,
            long sceneId,
            long memberId,
            String missionRunId) {
        if (!decision.isResult()) {
            return Mono.just(ResponseEntity.ok("false"));
        }

        return Mono.fromCallable(() ->
                        ImagePayloadDecoder.decodeDataUrlOrBase64(originalImage))
                .subscribeOn(Schedulers.parallel())
                .flatMap(decodedImage ->
                        dbComponent.saveData(
                                executionContext,
                                decodedImage,
                                sceneId,
                                memberId,
                                missionRunId))
                .thenReturn(ResponseEntity.ok("true"));
    }

    private String normalizeMissionRunId(String missionRunId) {
        if (missionRunId == null) {
            return UUID.randomUUID().toString();
        }
        String normalized = missionRunId.trim();
        if (normalized.isEmpty() || normalized.length() > 191) {
            return null;
        }
        return normalized;
    }
}
