package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class DiagnosticPoolEndpointTest {

    @Test
    void exposesPendingAcquireTimerAsTimerMeasurement() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        Timer timer = Timer.builder("reactor.netty.connection.provider.pending.connections.time")
                .tag("name", "doeng-external")
                .tag("remote.address", "experiment-mock:9100")
                .register(registry);
        timer.record(Duration.ofMillis(12));
        timer.record(Duration.ofMillis(28));

        List<Map<String, Object>> metrics = new DiagnosticPoolEndpoint(registry)
                .snapshot().get("metrics") instanceof List
                ? (List<Map<String, Object>>) new DiagnosticPoolEndpoint(registry)
                .snapshot().get("metrics")
                : List.of();

        Map<String, Object> measurement = metrics.stream()
                .filter(metric -> "reactor.netty.connection.provider.pending.connections.time"
                        .equals(metric.get("name")))
                .findFirst()
                .orElseThrow();
        assertEquals("TIMER", measurement.get("type"));
        assertEquals(2L, measurement.get("count"));
        assertEquals(40.0, (Double) measurement.get("totalTimeMs"), 0.001);
        assertEquals(20.0, (Double) measurement.get("meanMs"), 0.001);
        assertEquals(28.0, (Double) measurement.get("maxMs"), 0.001);
        assertFalse(((Map<?, ?>) measurement.get("tags")).isEmpty());
    }

    @Test
    void exposesConfiguredIsolatedProvidersWithoutMixingGaugeNames() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        registry.gauge("reactor.netty.connection.provider.active.connections",
                io.micrometer.core.instrument.Tags.of("name", "doeng-token"), 3, value -> value);
        registry.gauge("reactor.netty.connection.provider.active.connections",
                io.micrometer.core.instrument.Tags.of("name", "doeng-ai"), 4, value -> value);
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setPoolMode(ExternalPoolMode.ISOLATED);

        Map<String, Object> snapshot = new DiagnosticPoolEndpoint(registry, properties).snapshot();

        assertEquals("ISOLATED", snapshot.get("poolMode"));
        assertEquals(List.of("doeng-token", "doeng-ai", "doeng-storage"), snapshot.get("providers"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> metrics = (List<Map<String, Object>>) snapshot.get("metrics");
        assertEquals(2, metrics.size());
        assertEquals("doeng-token", ((Map<?, ?>) metrics.get(0).get("tags")).get("name"));
        assertEquals("doeng-ai", ((Map<?, ?>) metrics.get(1).get("tags")).get("name"));
    }
}
