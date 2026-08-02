package com.example.doenggameflux.contoller;

import com.example.doenggameflux.component.AiOutboundAdmissionGate;
import com.example.doenggameflux.component.DBComponentHttp;
import com.example.doenggameflux.component.DiagnosticErrorLogger;
import com.example.doenggameflux.component.StageObservation;
import com.example.doenggameflux.component.TokenComponent;
import com.example.doenggameflux.component.RequestIdentity;
import com.example.doenggameflux.dto.request.ImageRequestDto;
import com.example.doenggameflux.dto.response.AiDecisionResultDto;
import com.example.doenggameflux.util.ImagePayloadDecoder;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping
public class AiGameController {

    private final DBComponentHttp dbComponent;
    private final TokenComponent tokenComponent;
    private final WebClient aiWebClient;
    private final DiagnosticErrorLogger diagnosticErrorLogger;
    private final AiOutboundAdmissionGate aiAdmissionGate;
    private final StageObservation stageObservation;

    public AiGameController(
            DBComponentHttp dbComponent,
            TokenComponent tokenComponent,
            DiagnosticErrorLogger diagnosticErrorLogger,
            AiOutboundAdmissionGate aiAdmissionGate,
            StageObservation stageObservation,
            @Qualifier("aiWebClient") WebClient aiWebClient) {
        this.dbComponent = dbComponent;
        this.tokenComponent = tokenComponent;
        this.diagnosticErrorLogger = diagnosticErrorLogger;
        this.aiAdmissionGate = aiAdmissionGate;
        this.stageObservation = stageObservation;
        this.aiWebClient = aiWebClient;
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

        // The first remediation moves the existing admission boundary from the
        // AI call to the complete token -> AI -> storage -> DB request path.
        // The gate still fails fast and preserves the existing 503 mapping;
        // only the scope of the observation/admission boundary changes.
        Mono<ResponseEntity<String>> pipeline = Mono.zip(
                        image,
                        stageObservation.observe("TOKEN", aiAdmissionGate.executeStage(
                                com.example.doenggameflux.component.OutboundStage.TOKEN,
                                () -> tokenComponent.jwtConfirm(authorization))))
                .flatMap(tuple -> stageObservation.observe("AI", aiAdmissionGate.executeStage(
                        com.example.doenggameflux.component.OutboundStage.AI,
                        () -> requestDecision(
                        tuple.getT1(),
                        answer,
                        aiPath)))
                        .flatMap(decision -> completeIfMatched(
                                decision,
                                tuple.getT1().getImage(),
                                sceneId,
                                tuple.getT2(),
                                missionRunId)));
        return (aiAdmissionGate.isPerOutboundCall() ? pipeline : aiAdmissionGate.execute(() -> pipeline))
                .doOnError(error -> diagnosticErrorLogger.log(missionRunId, error))
                .onErrorResume(
                        WebClientResponseException.class,
                        error -> Mono.just(ResponseEntity
                                .status(error.getStatusCode())
                                .body(error.getResponseBodyAsString())));
    }

    Mono<AiDecisionResultDto> requestDecision(
            ImageRequestDto image,
            String answer,
            String aiPath) {
        Map<String, String> request = new HashMap<>();
        request.put("answer", answer);
        request.put("image", image.getImage());

        return Mono.deferContextual(contextView -> {
            RequestIdentity identity = RequestIdentity.from(contextView);
            WebClient.RequestBodySpec requestSpec = aiWebClient.post()
                    .uri(aiPath)
                    .contentType(MediaType.APPLICATION_JSON)
                    .accept(MediaType.APPLICATION_JSON);
            if (identity.hasExperimentRequestId()) {
                requestSpec.headers(headers -> {
                    headers.set(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER,
                            identity.getExperimentRequestId());
                    if (identity.getExperimentRunId() != null) {
                        headers.set(RequestIdentity.EXPERIMENT_RUN_ID_HEADER,
                                identity.getExperimentRunId());
                    }
                    if (identity.getMissionRunId() != null) {
                        headers.set(RequestIdentity.MISSION_RUN_ID_HEADER,
                                identity.getMissionRunId());
                    }
                });
            }
            return requestSpec
                    .bodyValue(request)
                    .retrieve()
                    // The deployed AI still returns an image echo. REST storage
                    // intentionally consumes only its decision and retains the
                    // original request image for a successful upload.
                    .bodyToMono(AiDecisionResultDto.class);
        });
    }

    private Mono<ResponseEntity<String>> completeIfMatched(
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
