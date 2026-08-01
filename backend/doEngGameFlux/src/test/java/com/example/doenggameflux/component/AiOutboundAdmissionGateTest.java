package com.example.doenggameflux.component;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.example.doenggameflux.config.AdmissionProperties;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;

class AiOutboundAdmissionGateTest {

    @Test
    void rejectsWithoutWaitingAndReleasesOnCompletion() {
        AdmissionProperties properties = new AdmissionProperties();
        properties.setEnabled(true);
        properties.setMaxConcurrent(1);
        AiOutboundAdmissionGate gate = new AiOutboundAdmissionGate(properties, new SimpleMeterRegistry());

        Mono<Void> held = gate.execute(() -> Mono.never());
        reactor.core.Disposable subscription = held.subscribe();

        assertThrows(AiCapacityExceededException.class,
                () -> gate.execute(() -> Mono.empty()).block());
        assertEquals(1, gate.snapshot().getCurrentInUse());

        subscription.dispose();
        assertEquals(0, gate.snapshot().getCurrentInUse());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void releasesOnError() {
        AdmissionProperties properties = new AdmissionProperties();
        properties.setEnabled(true);
        properties.setMaxConcurrent(1);
        AiOutboundAdmissionGate gate = new AiOutboundAdmissionGate(properties, new SimpleMeterRegistry());

        assertThrows(IllegalStateException.class,
                () -> gate.execute(() -> Mono.error(new IllegalStateException("boom"))).block());
        assertEquals(0, gate.snapshot().getCurrentInUse());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void disabledGatePreservesActionWithoutPermitAccounting() {
        AdmissionProperties properties = new AdmissionProperties();
        properties.setEnabled(false);
        properties.setMaxConcurrent(1);
        AiOutboundAdmissionGate gate = new AiOutboundAdmissionGate(properties, new SimpleMeterRegistry());

        assertEquals("ok", gate.execute(() -> Mono.just("ok")).block());
        assertEquals(0, gate.snapshot().getCurrentInUse());
        assertEquals(0, gate.snapshot().getAcquired());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void perOutboundStageUsesSharedBudgetAndReleasesExactlyOnce() {
        AdmissionProperties properties = new AdmissionProperties();
        properties.setEnabled(true);
        properties.setMode("PER_OUTBOUND_CALL");
        properties.setMaxConcurrent(1);
        AiOutboundAdmissionGate gate = new AiOutboundAdmissionGate(properties, new SimpleMeterRegistry());

        assertEquals("ok", gate.executeStage(OutboundStage.TOKEN, () -> Mono.just("ok")).block());
        assertEquals(1, gate.stageSnapshot().get("TOKEN").getAcquired());
        assertEquals(1, gate.stageSnapshot().get("TOKEN").getReleased());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }
}
