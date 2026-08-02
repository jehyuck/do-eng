package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

import com.example.doenggameflux.component.RequestIdentity;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import org.springframework.web.server.WebFilterChain;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

class TransportRequestObservationFilterTest {

    @Test
    void propagatesAllHeadersIntoReactorContext() {
        TransportAttributionProperties properties = new TransportAttributionProperties();
        properties.setEnabled(true);
        TransportRequestObservationFilter filter = new TransportRequestObservationFilter(properties);
        AtomicReference<RequestIdentity> captured = new AtomicReference<>();
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/game/face")
                        .header(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER, "request-1")
                        .header(RequestIdentity.EXPERIMENT_RUN_ID_HEADER, "run-1")
                        .header(RequestIdentity.MISSION_RUN_ID_HEADER, "mission-1"));
        WebFilterChain chain = ignored -> Mono.deferContextual(context -> {
            captured.set(RequestIdentity.from(context));
            return Mono.empty();
        });

        StepVerifier.create(filter.filter(exchange, chain)).verifyComplete();

        assertEquals(new RequestIdentity("request-1", "run-1", "mission-1"), captured.get());
    }

    @Test
    void missingHeadersCompleteNormally() {
        TransportAttributionProperties properties = new TransportAttributionProperties();
        properties.setEnabled(true);
        TransportRequestObservationFilter filter = new TransportRequestObservationFilter(properties);
        AtomicReference<Boolean> invoked = new AtomicReference<>(false);
        WebFilterChain chain = ignored -> Mono.fromRunnable(() -> invoked.set(true));

        StepVerifier.create(filter.filter(
                MockServerWebExchange.from(MockServerHttpRequest.get("/test")), chain))
                .verifyComplete();

        assertEquals(Boolean.TRUE, invoked.get());
    }

    @Test
    void errorAndCancellationSignalsRemainUnchanged() {
        TransportAttributionProperties properties = new TransportAttributionProperties();
        properties.setEnabled(true);
        TransportRequestObservationFilter filter = new TransportRequestObservationFilter(properties);
        MockServerWebExchange errorExchange = exchange("error-request");
        StepVerifier.create(filter.filter(errorExchange,
                        ignored -> Mono.error(new IllegalStateException("boom"))))
                .expectError(IllegalStateException.class)
                .verify();

        MockServerWebExchange cancelExchange = exchange("cancel-request");
        Disposable subscription = filter.filter(cancelExchange, ignored -> Mono.never()).subscribe();
        subscription.dispose();
        assertFalse(subscription.isDisposed() && cancelExchange.getResponse().isCommitted());
    }

    private MockServerWebExchange exchange(String requestId) {
        return MockServerWebExchange.from(MockServerHttpRequest.post("/game/face")
                .header(RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER, requestId));
    }
}
