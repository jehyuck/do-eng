package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.resources.ConnectionProvider;

class ExternalHttpClientConfigTest {

    @Test
    void createsDedicatedProviderAndClientBeansForIsolatedMode() {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setPoolMode(ExternalPoolMode.ISOLATED);
        properties.setSharedPool(new ExternalServiceProperties.PoolSettings(400, 800));
        DiagnosticProperties diagnosticProperties = new DiagnosticProperties();
        ExternalHttpClientConfig config = new ExternalHttpClientConfig();

        ConnectionProvider shared = config.sharedConnectionProvider(properties, diagnosticProperties);
        ConnectionProvider token = config.tokenConnectionProvider(properties, diagnosticProperties);
        ConnectionProvider ai = config.aiConnectionProvider(properties, diagnosticProperties);
        ConnectionProvider storage = config.storageConnectionProvider(properties, diagnosticProperties);
        try {
            assertNotNull(config.tokenWebClient(properties, shared, token, diagnosticProperties));
            assertNotNull(config.aiWebClient(properties, shared, ai, diagnosticProperties));
            assertNotNull(config.storageWebClient(properties, shared, storage, diagnosticProperties));
            assertNotNull(shared);
            assertEquals("doeng-token", token.name());
            assertEquals("doeng-ai", ai.name());
            assertEquals("doeng-storage", storage.name());
            assertNotEquals(token.name(), ai.name());
            assertNotEquals(token.name(), storage.name());
            assertNotEquals(ai.name(), storage.name());
        } finally {
            shared.dispose();
            token.dispose();
            ai.dispose();
            storage.dispose();
        }
    }
}
