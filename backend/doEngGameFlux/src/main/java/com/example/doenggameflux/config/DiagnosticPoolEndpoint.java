package com.example.doenggameflux.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.util.concurrent.TimeUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/** Targeted Reactor Netty pool view used by low-interference experiments. */
@Component
@Endpoint(id = "doengdiagnosticpool")
@ConditionalOnProperty(name = "doeng.pool-observation.enabled", havingValue = "true")
public class DiagnosticPoolEndpoint {

    private static final String PREFIX = "reactor.netty.connection.provider.";

    private final MeterRegistry registry;

    public DiagnosticPoolEndpoint(MeterRegistry registry) {
        this.registry = registry;
    }

    @ReadOperation
    public Map<String, Object> snapshot() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("capturedAtEpochMs", System.currentTimeMillis());
        response.put("provider", "doeng-external");
        response.put("metrics", measurements());
        return response;
    }

    private List<Map<String, Object>> measurements() {
        List<Map<String, Object>> values = new ArrayList<>();
        for (String suffix : new String[]{
                "active.connections",
                "idle.connections",
                "total.connections",
                "max.connections",
                "pending.connections",
                "max.pending.connections"}) {
            for (Gauge gauge : registry.find(PREFIX + suffix).gauges()) {
                Map<String, Object> value = new LinkedHashMap<>();
                value.put("name", PREFIX + suffix);
                value.put("value", finiteOrNull(gauge.value()));
                value.put("tags", tags(gauge.getId()));
                values.add(value);
            }
        }
        for (Timer timer : registry.find(PREFIX + "pending.connections.time").timers()) {
            Map<String, Object> value = new LinkedHashMap<>();
            value.put("name", PREFIX + "pending.connections.time");
            value.put("type", "TIMER");
            value.put("count", timer.count());
            value.put("totalTimeMs", timer.totalTime(TimeUnit.MILLISECONDS));
            value.put("meanMs", timer.mean(TimeUnit.MILLISECONDS));
            value.put("maxMs", timer.max(TimeUnit.MILLISECONDS));
            Map<String, Double> percentiles = new LinkedHashMap<>();
            for (io.micrometer.core.instrument.distribution.ValueAtPercentile percentile
                    : timer.takeSnapshot().percentileValues()) {
                percentiles.put(Double.toString(percentile.percentile()),
                        percentile.value(TimeUnit.MILLISECONDS));
            }
            value.put("percentiles", percentiles);
            value.put("tags", tags(timer.getId()));
            values.add(value);
        }
        return values;
    }

    private Double finiteOrNull(double value) {
        return Double.isFinite(value) ? value : null;
    }

    private Map<String, String> tags(Meter.Id id) {
        Map<String, String> tags = new LinkedHashMap<>();
        id.getTags().forEach(tag -> tags.put(tag.getKey(), tag.getValue()));
        return tags;
    }
}
