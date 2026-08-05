package com.example.doenggameflux.config;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Meter;
import io.micrometer.core.instrument.composite.CompositeMeterRegistry;
import io.micrometer.core.instrument.Tag;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/** Read-only identity view enabled only for the Exp131 diagnostic profile. */
@Component
@Endpoint(id = "doengidentity")
@ConditionalOnProperty(name = "doeng.identity-probe.enabled", havingValue = "true")
public class DiagnosticIdentityEndpoint {
    private static final String PREFIX = "reactor.netty.connection.provider.";
    private final ExternalClientIdentityRegistry identities;
    private final MeterRegistry registry;

    public DiagnosticIdentityEndpoint(ExternalClientIdentityRegistry identities,
            MeterRegistry registry) {
        this.identities = identities;
        this.registry = registry;
    }

    @ReadOperation
    public Map<String, Object> snapshot() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("capturedAtEpochMs", System.currentTimeMillis());
        result.put("clients", identities.snapshot());
        result.put("meterRegistry", registryInfo());
        result.put("meters", meterDump());
        result.put("poolSeries", poolSeries());
        return result;
    }

    private Map<String, Object> registryInfo() {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("class", registry.getClass().getName());
        info.put("identity", System.identityHashCode(registry));
        info.put("meterCount", registry.getMeters().size());
        if (registry instanceof CompositeMeterRegistry) {
            List<Map<String, Object>> children = new ArrayList<>();
            for (MeterRegistry child : ((CompositeMeterRegistry) registry).getRegistries()) {
                children.add(Map.of("class", child.getClass().getName(),
                        "identity", System.identityHashCode(child),
                        "meterCount", child.getMeters().size()));
            }
            info.put("children", children);
        }
        return info;
    }

    private List<Map<String, Object>> meterDump() {
        List<Map<String, Object>> result = new ArrayList<>();
        for (Meter meter : registry.getMeters()) {
            String name = meter.getId().getName();
            if (!name.startsWith("reactor.netty.connection.provider")
                    && !name.startsWith("reactor.netty.http.client")) {
                continue;
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("name", name);
            row.put("type", meter.getId().getType().name());
            row.put("description", meter.getId().getDescription());
            row.put("baseUnit", meter.getId().getBaseUnit());
            row.put("tags", meter.getId().getTags().stream().collect(
                    java.util.stream.Collectors.toMap(Tag::getKey, Tag::getValue,
                            (a, b) -> b, LinkedHashMap::new)));
            row.put("meterId", meter.getId().toString());
            row.put("meterIdHashCode", meter.getId().hashCode());
            row.put("measurements", meter.measure());
            result.add(row);
        }
        return result;
    }

    private List<Map<String, Object>> poolSeries() {
        List<Map<String, Object>> result = new ArrayList<>();
        for (Map<String, Object> meter : meterDump()) {
            String name = String.valueOf(meter.get("name"));
            if (name.startsWith(PREFIX)) {
                result.add(meter);
            }
        }
        return result;
    }
}
