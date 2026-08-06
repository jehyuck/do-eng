package com.example.doenggameflux.contoller;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.example.doenggameflux.component.AiDispatchRequest;
import com.example.doenggameflux.component.AiDispatcher;
import com.example.doenggameflux.component.RequestIdentity;
import com.example.doenggameflux.dispatcher.MissionExecutionContext;
import com.example.doenggameflux.dto.request.ImageRequestDto;
import java.time.Duration;
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
    void aiDispatcherUsesExplicitRequestIdentity() throws Exception {
        AtomicReference<ClientRequest> captured = new AtomicReference<>();
        WebClient client = WebClient.builder().exchangeFunction(request -> {
            captured.set(request);
            return Mono.just(ClientResponse.create(HttpStatus.OK)
                    .header("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                    .body("{\"result\":false,\"image\":null}")
                    .build());
        }).build();
        AiDispatcher dispatcher = new AiDispatcher(client, 1, 1);
        dispatcher.afterPropertiesSet();
        RequestIdentity identity = new RequestIdentity("request-1", "run-1", "mission-1");

        try {
            StepVerifier.create(dispatcher.dispatch(
                            MissionExecutionContext.start("mission-1", Duration.ofSeconds(2)),
                            new AiDispatchRequest(
                                    new ImageRequestDto("data:image/jpeg;base64,AA=="),
                                    "happy",
                                    "/face",
                                    identity)))
                    .expectNextMatches(result -> !result.isResult())
                    .verifyComplete();
        } finally {
            dispatcher.destroy();
        }

        assertEquals("request-1", captured.get().headers()
                .getFirst(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER));
        assertEquals("run-1", captured.get().headers()
                .getFirst(RequestIdentity.EXPERIMENT_RUN_ID_HEADER));
        assertEquals("mission-1", captured.get().headers()
                .getFirst(RequestIdentity.MISSION_RUN_ID_HEADER));
    }

    @Test
    void missingDiagnosticIdentityAddsNoCorrelationHeaders() throws Exception {
        AtomicReference<ClientRequest> captured = new AtomicReference<>();
        WebClient client = WebClient.builder().exchangeFunction(request -> {
            captured.set(request);
            return Mono.just(ClientResponse.create(HttpStatus.OK)
                    .header("Content-Type", MediaType.APPLICATION_JSON_VALUE)
                    .body("{\"result\":false}")
                    .build());
        }).build();
        AiDispatcher dispatcher = new AiDispatcher(client, 1, 1);
        dispatcher.afterPropertiesSet();

        try {
            StepVerifier.create(dispatcher.dispatch(
                            MissionExecutionContext.start("mission-1", Duration.ofSeconds(2)),
                            new AiDispatchRequest(
                                    new ImageRequestDto("data:image/jpeg;base64,AA=="),
                                    "happy",
                                    "/face",
                                    new RequestIdentity(null, null, null))))
                    .expectNextCount(1)
                    .verifyComplete();
        } finally {
            dispatcher.destroy();
        }

        assertEquals(null, captured.get().headers()
                .getFirst(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER));
    }

    @Test
    void downstreamErrorPropagatesUnchanged() throws Exception {
        IllegalStateException failure = new IllegalStateException("downstream failure");
        WebClient client = WebClient.builder()
                .exchangeFunction(request -> Mono.error(failure))
                .build();
        AiDispatcher dispatcher = new AiDispatcher(client, 1, 1);
        dispatcher.afterPropertiesSet();

        try {
            StepVerifier.create(dispatcher.dispatch(
                            MissionExecutionContext.start("mission-1", Duration.ofSeconds(2)),
                            new AiDispatchRequest(
                                    new ImageRequestDto("data:image/jpeg;base64,AA=="),
                                    "happy",
                                    "/face",
                                    new RequestIdentity(null, null, null))))
                    .expectErrorMatches(error -> error == failure)
                    .verify();
        } finally {
            dispatcher.destroy();
        }
    }
}
