package com.example.doenggameflux.dispatcher;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Duration;
import java.util.ArrayDeque;
import java.util.Queue;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Sinks;

class DispatcherMetricsTest {

    @Test
    void exposesStageIsolatedGaugesAndEvents() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        DispatcherMetrics metrics = new DispatcherMetrics(registry);
        Queue<Integer> queue = new ArrayDeque<>();
        AtomicInteger active = new AtomicInteger();

        metrics.bind("token", queue, active);
        queue.add(1);
        active.set(2);
        metrics.enqueued("token");
        metrics.dequeued("token", Duration.ofMillis(12));
        metrics.rejected("token");
        metrics.deadline("token", "BEFORE_EXECUTION");
        metrics.resultEmissionFailure("token", Sinks.EmitResult.FAIL_CANCELLED);

        assertEquals(1.0, registry.get("doeng.dispatcher.queue.depth")
                .tag("dispatcher", "token").gauge().value());
        assertEquals(2.0, registry.get("doeng.dispatcher.active")
                .tag("dispatcher", "token").gauge().value());
        assertEquals(1.0, registry.get("doeng.dispatcher.events")
                .tags("dispatcher", "token", "event", "rejected", "detail", "queue_full")
                .counter().count());
        assertNotNull(registry.get("doeng.dispatcher.queue.wait")
                .tag("dispatcher", "token").timer());
    }
}
