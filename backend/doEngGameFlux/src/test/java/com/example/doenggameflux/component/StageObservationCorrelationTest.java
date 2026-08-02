package com.example.doenggameflux.component;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.junit.jupiter.api.Assertions.assertSame;

import com.example.doenggameflux.config.StageObservationProperties;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

class StageObservationCorrelationTest {

    @Test
    void diagnosticOffReturnsExistingPublisherUnchanged() {
        StageObservationProperties properties = new StageObservationProperties();
        properties.setEnabled(false);
        StageObservation observation = new StageObservation(properties);
        Mono<String> source = Mono.just("unchanged");

        assertSame(source, observation.observe("AI", source));
    }

    @Test
    void logsOneRequestScopedFailureWithoutChangingError() {
        StageObservationProperties properties = new StageObservationProperties();
        properties.setEnabled(true);
        DiagnosticErrorLogger logger = mock(DiagnosticErrorLogger.class);
        StageObservation observation = new StageObservation(properties, logger);
        RequestIdentity identity = new RequestIdentity("request-1", "run-1", "mission-1");
        IllegalStateException failure = new IllegalStateException("boom");

        StepVerifier.create(observation.observe("AI", Mono.error(failure))
                        .contextWrite(identity::writeTo))
                .expectErrorMatches(error -> error == failure)
                .verify();

        verify(logger, times(1)).logStageEvent(identity, "AI", "STAGE_STARTED", null);
        verify(logger, times(1)).logStageEvent(identity, "AI", "STAGE_FAILED", failure);
        verify(logger, times(1)).logStageEvent(identity, "AI", "STAGE_TERMINATED", null);
    }
}
