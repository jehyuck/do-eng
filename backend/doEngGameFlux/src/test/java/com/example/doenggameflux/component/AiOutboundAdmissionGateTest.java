package com.example.doenggameflux.component;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.example.doenggameflux.config.AdmissionMode;
import com.example.doenggameflux.config.AdmissionProperties;
import com.example.doenggameflux.config.AdmissionScope;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

class AiOutboundAdmissionGateTest {

    @Test
    void enforceRejectsLazilyWithoutSubscribingDownstream() {
        AdmissionProperties properties = properties(AdmissionMode.ENFORCE, 1);
        AiOutboundAdmissionGate gate = gate(properties);
        AtomicInteger bodySubscriptions = new AtomicInteger();
        AtomicInteger tokenCalls = new AtomicInteger();
        AtomicInteger aiCalls = new AtomicInteger();
        AtomicInteger storageCalls = new AtomicInteger();
        AtomicInteger dbCalls = new AtomicInteger();
        Disposable held = gate.execute(() -> Mono.never()).subscribe();

        Mono<String> rejected = gate.execute(() -> {
            bodySubscriptions.incrementAndGet();
            tokenCalls.incrementAndGet();
            aiCalls.incrementAndGet();
            storageCalls.incrementAndGet();
            dbCalls.incrementAndGet();
            return Mono.just("should-not-run");
        });

        StepVerifier.create(rejected)
                .expectError(AiCapacityExceededException.class)
                .verify();
        assertEquals(0, bodySubscriptions.get());
        assertEquals(0, tokenCalls.get());
        assertEquals(0, aiCalls.get());
        assertEquals(0, storageCalls.get());
        assertEquals(0, dbCalls.get());
        assertEquals(1, gate.snapshot().getRejected());
        held.dispose();
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void enforceAddsOnlyAllowedRequestsAndReleasesOnSuccess() {
        AiOutboundAdmissionGate gate = gate(properties(AdmissionMode.ENFORCE, 1));
        assertEquals("ok", gate.execute(() -> Mono.just("ok")).block());
        assertEquals(1, gate.snapshot().getStarted());
        assertEquals(1, gate.snapshot().getCompleted());
        assertEquals(1, gate.snapshot().getReleased());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void releasesOnErrorAndSynchronousSupplierFailure() {
        AiOutboundAdmissionGate gate = gate(properties(AdmissionMode.ENFORCE, 2));
        assertThrows(IllegalStateException.class,
                () -> gate.execute(() -> Mono.error(new IllegalStateException("boom"))).block());
        assertThrows(IllegalArgumentException.class,
                () -> gate.execute(() -> { throw new IllegalArgumentException("supplier"); }).block());
        assertEquals(2, gate.snapshot().getCompleted());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void releasesOnCancellation() {
        AiOutboundAdmissionGate gate = gate(properties(AdmissionMode.ENFORCE, 1));
        Disposable subscription = gate.execute(() -> Mono.never()).subscribe();
        assertEquals(1, gate.snapshot().getCurrentInUse());
        subscription.dispose();
        assertEquals(0, gate.snapshot().getCurrentInUse());
        assertEquals(1, gate.snapshot().getCancelled());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void observeDoesNotRejectOverLimitAndRecordsWouldReject() {
        AiOutboundAdmissionGate gate = gate(properties(AdmissionMode.OBSERVE, 1));
        Disposable first = gate.execute(() -> Mono.never()).subscribe();
        Disposable second = gate.execute(() -> Mono.just("accepted")).subscribe();
        assertTrue(second.isDisposed());
        assertEquals(2, gate.snapshot().getMaxObservedInUse());
        assertEquals(1, gate.snapshot().getWouldReject());
        assertEquals(0, gate.snapshot().getRejected());
        first.dispose();
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void compareAndSetNeverExceedsEnforceLimitUnderRace() throws Exception {
        AiOutboundAdmissionGate gate = gate(properties(AdmissionMode.ENFORCE, 4));
        CountDownLatch start = new CountDownLatch(1);
        CountDownLatch ready = new CountDownLatch(8);
        Disposable[] subscriptions = new Disposable[8];
        for (int i = 0; i < subscriptions.length; i++) {
            final int index = i;
            Thread thread = new Thread(() -> {
                ready.countDown();
                try {
                    start.await(2, TimeUnit.SECONDS);
                    subscriptions[index] = gate.execute(() -> Mono.never()).subscribe();
                } catch (InterruptedException error) {
                    Thread.currentThread().interrupt();
                }
            });
            thread.start();
        }
        assertTrue(ready.await(2, TimeUnit.SECONDS));
        start.countDown();
        Thread.sleep(100);
        assertTrue(gate.snapshot().getMaxObservedInUse() <= 4);
        for (Disposable subscription : subscriptions) {
            if (subscription != null) {
                subscription.dispose();
            }
        }
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void offPreservesActionWithoutAccounting() {
        AdmissionProperties properties = properties(AdmissionMode.OFF, 1);
        AiOutboundAdmissionGate gate = gate(properties);
        assertEquals("ok", gate.execute(() -> Mono.just("ok")).block());
        assertEquals(0, gate.snapshot().getStarted());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    @Test
    void perOutboundCompatibilityUsesTheSameBudget() {
        AdmissionProperties properties = properties(AdmissionMode.ENFORCE, 1);
        properties.setScope(AdmissionScope.PER_OUTBOUND_CALL);
        AiOutboundAdmissionGate gate = gate(properties);
        assertEquals("ok", gate.executeStage(OutboundStage.TOKEN, () -> Mono.just("ok")).block());
        assertEquals(1, gate.stageSnapshot().get("TOKEN").getStarted());
        assertEquals(1, gate.stageSnapshot().get("TOKEN").getReleased());
        assertEquals(0, gate.snapshot().getPermitLeak());
    }

    private static AdmissionProperties properties(AdmissionMode mode, int limit) {
        AdmissionProperties properties = new AdmissionProperties();
        properties.setMode(mode);
        properties.setMaxConcurrent(limit);
        return properties;
    }

    private static AiOutboundAdmissionGate gate(AdmissionProperties properties) {
        return new AiOutboundAdmissionGate(properties, new SimpleMeterRegistry());
    }
}
