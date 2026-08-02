package com.example.doenggameflux.contoller;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.example.doenggameflux.component.RequestIdentity;
import com.example.doenggameflux.dto.request.ImageRequestDto;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.client.ClientRequest;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

class AiGameControllerCorrelationTest {

    @Test
    void aiRequestUsesIdentityFromReactorContext() {
        AtomicReference<ClientRequest> captured = new AtomicReference<>();
        WebClient client = WebClient.builder().exchangeFunction(request -> {
            captured.set(request);
            return Mono.just(ClientResponse.create(HttpStatus.OK)
                    .header("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                    .body("{\"result\":false,\"image\":null}")
                    .build());
        }).build();
        AiGameController controller = new AiGameController(null, null, null, null, null, client);
        RequestIdentity identity = new RequestIdentity("request-1", "run-1", "mission-1");

        StepVerifier.create(controller.requestDecision(
                        new ImageRequestDto("data:image/jpeg;base64,AA=="), "happy", "/face")
                        .contextWrite(identity::writeTo))
                .expectNextMatches(result -> !result.isResult())
                .verifyComplete();

        assertEquals("request-1", captured.get().headers()
                .getFirst(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER));
        assertEquals("run-1", captured.get().headers()
                .getFirst(RequestIdentity.EXPERIMENT_RUN_ID_HEADER));
        assertEquals("mission-1", captured.get().headers()
                .getFirst(RequestIdentity.MISSION_RUN_ID_HEADER));
    }

    @Test
    void noDiagnosticIdentityAddsNoCorrelationHeaders() {
        AtomicReference<ClientRequest> captured = new AtomicReference<>();
        WebClient client = WebClient.builder().exchangeFunction(request -> {
            captured.set(request);
            return Mono.just(ClientResponse.create(HttpStatus.OK)
                    .header("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                    .body("{\"result\":false}")
                    .build());
        }).build();
        AiGameController controller = new AiGameController(null, null, null, null, null, client);

        StepVerifier.create(controller.requestDecision(
                        new ImageRequestDto("data:image/jpeg;base64,AA=="), "happy", "/face"))
                .expectNextCount(1)
                .verifyComplete();

        assertEquals(null, captured.get().headers()
                .getFirst(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER));
    }

    @Test
    void downstreamErrorPropagatesUnchangedWithoutDiagnosticIdentity() {
        IllegalStateException failure = new IllegalStateException("downstream failure");
        WebClient client = WebClient.builder()
                .exchangeFunction(request -> Mono.error(failure))
                .build();
        AiGameController controller = new AiGameController(null, null, null, null, null, client);

        StepVerifier.create(controller.requestDecision(
                        new ImageRequestDto("data:image/jpeg;base64,AA=="), "happy", "/face"))
                .expectErrorMatches(error -> error == failure)
                .verify();
    }
}
