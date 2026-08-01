package com.example.doenggameflux.component;

import com.example.doenggameflux.config.StageObservationProperties;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class StageObservationTest {

    @Test
    void disabledObservationPreservesSource() {
        StageObservationProperties properties = new StageObservationProperties();
        StageObservation observation = new StageObservation(properties);

        StepVerifier.create(observation.observe("AI", Mono.just("ok")))
                .expectNext("ok")
                .verifyComplete();

        assertTrue(observation.snapshot().isEmpty());
    }

    @Test
    void enabledObservationRecordsSuccessAndFailureWithoutChangingSignals() {
        StageObservationProperties properties = new StageObservationProperties();
        properties.setEnabled(true);
        StageObservation observation = new StageObservation(properties);

        StepVerifier.create(observation.observe("AI", Mono.just("ok")))
                .expectNext("ok")
                .verifyComplete();
        StepVerifier.create(observation.observe("AI", Mono.error(new IllegalStateException("boom"))))
                .expectError(IllegalStateException.class)
                .verify();

        List<Map<String, Object>> snapshot = observation.snapshot();
        assertEquals(1, snapshot.size());
        assertEquals(2L, snapshot.get(0).get("started"));
        assertEquals(1L, snapshot.get(0).get("succeeded"));
        assertEquals(1L, snapshot.get(0).get("failed"));
        assertEquals(0, snapshot.get(0).get("inFlight"));
    }
}
