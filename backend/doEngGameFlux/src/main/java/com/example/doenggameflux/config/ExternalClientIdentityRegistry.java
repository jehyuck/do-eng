package com.example.doenggameflux.config;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Component;

/** Read-only identity registry used only by the Exp131 diagnostic endpoint. */
@Component
public class ExternalClientIdentityRegistry {
    private final Map<String, Map<String, Object>> clients = new ConcurrentHashMap<>();

    public void register(String logicalClient, Object webClient, Object httpClient,
            Object provider, String providerName, String baseUrl) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("logicalClient", logicalClient);
        value.put("webClientIdentity", System.identityHashCode(webClient));
        value.put("httpClientIdentity", System.identityHashCode(httpClient));
        value.put("providerIdentity", System.identityHashCode(provider));
        value.put("providerName", providerName);
        value.put("baseUrl", baseUrl);
        clients.put(logicalClient, value);
    }

    public Map<String, Map<String, Object>> snapshot() {
        return new LinkedHashMap<>(clients);
    }
}
