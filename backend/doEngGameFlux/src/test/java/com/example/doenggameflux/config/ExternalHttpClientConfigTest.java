package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertNotNull;

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
            assertNotNull(config.tokenWebClient(properties, token, diagnosticProperties));
            assertNotNull(config.aiWebClient(properties, ai, diagnosticProperties));
            assertNotNull(config.storageWebClient(properties, storage, diagnosticProperties));
            assertNotNull(shared);
        } finally {
            shared.dispose();
            token.dispose();
            ai.dispose();
            storage.dispose();
        }
    }
}
