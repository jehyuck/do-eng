package com.example.doenggameflux.config;

import io.netty.channel.ChannelOption;
import com.example.doenggameflux.component.TransportDiagnosticLogger;
import com.example.doenggameflux.component.TransportHttpClientObservation;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

@Configuration
public class ExternalHttpClientConfig {

    // Compatibility overloads keep the existing configuration unit tests and
    // callers source-compatible; diagnostic observation is disabled here.
    public WebClient tokenWebClient(
            ExternalServiceProperties properties,
            ConnectionProvider sharedProvider,
            ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties) {
        TransportAttributionProperties transportProperties = new TransportAttributionProperties();
        return tokenWebClient(properties, sharedProvider, isolatedProvider, diagnosticProperties,
                transportProperties, new TransportDiagnosticLogger(transportProperties), null);
    }

    public WebClient aiWebClient(
            ExternalServiceProperties properties,
            ConnectionProvider sharedProvider,
            ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties) {
        TransportAttributionProperties transportProperties = new TransportAttributionProperties();
        return aiWebClient(properties, sharedProvider, isolatedProvider, diagnosticProperties,
                transportProperties, new TransportDiagnosticLogger(transportProperties), null);
    }

    public WebClient storageWebClient(
            ExternalServiceProperties properties,
            ConnectionProvider sharedProvider,
            ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties) {
        TransportAttributionProperties transportProperties = new TransportAttributionProperties();
        return storageWebClient(properties, sharedProvider, isolatedProvider, diagnosticProperties,
                transportProperties, new TransportDiagnosticLogger(transportProperties), null);
    }

    @Value("${doeng.experiment.metrics.enabled:false}")
    private boolean experimentMetricsEnabled;

    @Value("${doeng.pool-observation.enabled:false}")
    private boolean poolObservationEnabled;

    @Bean(name = {"sharedConnectionProvider", "externalConnectionProvider"},
            destroyMethod = "dispose")
    public ConnectionProvider sharedConnectionProvider(
            ExternalServiceProperties properties,
            DiagnosticProperties diagnosticProperties) {
        return buildProvider(
                "doeng-external",
                properties.getSharedPool(),
                properties,
                diagnosticProperties);
    }

    @Bean(name = "tokenConnectionProvider", destroyMethod = "dispose")
    public ConnectionProvider tokenConnectionProvider(
            ExternalServiceProperties properties,
            DiagnosticProperties diagnosticProperties) {
        return buildProvider(
                "doeng-token",
                properties.getTokenPool(),
                properties,
                diagnosticProperties);
    }

    @Bean(name = "aiConnectionProvider", destroyMethod = "dispose")
    public ConnectionProvider aiConnectionProvider(
            ExternalServiceProperties properties,
            DiagnosticProperties diagnosticProperties) {
        return buildProvider(
                "doeng-ai",
                properties.getAiPool(),
                properties,
                diagnosticProperties);
    }

    @Bean(name = "storageConnectionProvider", destroyMethod = "dispose")
    public ConnectionProvider storageConnectionProvider(
            ExternalServiceProperties properties,
            DiagnosticProperties diagnosticProperties) {
        return buildProvider(
                "doeng-storage",
                properties.getStoragePool(),
                properties,
                diagnosticProperties);
    }

    @Bean("tokenWebClient")
    public WebClient tokenWebClient(
            ExternalServiceProperties properties,
            @Qualifier("sharedConnectionProvider") ConnectionProvider sharedProvider,
            @Qualifier("tokenConnectionProvider") ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger,
            ExternalClientIdentityRegistry identityRegistry) {
        return buildClient(properties, selectProvider(properties, sharedProvider, isolatedProvider),
                properties.getTokenVerificationUrl(), diagnosticProperties, "TOKEN",
                transportProperties, transportLogger, identityRegistry);
    }

    @Bean("aiWebClient")
    public WebClient aiWebClient(
            ExternalServiceProperties properties,
            @Qualifier("sharedConnectionProvider") ConnectionProvider sharedProvider,
            @Qualifier("aiConnectionProvider") ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger,
            ExternalClientIdentityRegistry identityRegistry) {
        ConnectionProvider provider = selectProvider(properties, sharedProvider, isolatedProvider);
        HttpClient httpClient = buildHttpClient(properties, provider, diagnosticProperties, "AI",
                transportProperties, transportLogger);
        WebClient client = WebClient.builder()
                .defaultHeader("X-Experiment-Stage", "AI")
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .baseUrl(properties.getAiBaseUrl())
                .codecs(configurer ->
                        configurer.defaultCodecs().maxInMemorySize(2 * 1024 * 1024))
                .build();
        registerIdentity(identityRegistry, "AI", client, httpClient, provider,
                properties.getAiBaseUrl());
        return client;
    }

    @Bean("storageWebClient")
    public WebClient storageWebClient(
            ExternalServiceProperties properties,
            @Qualifier("sharedConnectionProvider") ConnectionProvider sharedProvider,
            @Qualifier("storageConnectionProvider") ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger,
            ExternalClientIdentityRegistry identityRegistry) {
        return buildClient(properties, selectProvider(properties, sharedProvider, isolatedProvider),
                properties.getStorageBaseUrl(), diagnosticProperties, "STORAGE",
                transportProperties, transportLogger, identityRegistry);
    }

    private ConnectionProvider buildProvider(
            String name,
            ExternalServiceProperties.PoolSettings settings,
            ExternalServiceProperties properties,
            DiagnosticProperties diagnosticProperties) {
        properties.validatePoolContract();
        ConnectionProvider.Builder builder = ConnectionProvider.builder(name)
                .maxConnections(settings.getMaxConnections())
                .pendingAcquireMaxCount(settings.getPendingAcquireMaxCount())
                .pendingAcquireTimeout(Duration.ofMillis(
                        properties.getPendingAcquireTimeoutMs()));
        if (properties.getLeasingStrategy() == ExternalLeasingStrategy.LIFO) {
            builder.lifo();
        }
        if (properties.getMaxIdleTimeMs() > 0) {
            builder.maxIdleTime(Duration.ofMillis(properties.getMaxIdleTimeMs()));
        }
        if (properties.getBackgroundEvictionIntervalMs() > 0) {
            builder.evictInBackground(Duration.ofMillis(
                    properties.getBackgroundEvictionIntervalMs()));
        }
        if (experimentMetricsEnabled || diagnosticProperties.isEnabled() || poolObservationEnabled) {
            builder.metrics(true);
        }
        return builder.build();
    }

    private ConnectionProvider selectProvider(
            ExternalServiceProperties properties,
            ConnectionProvider sharedProvider,
            ConnectionProvider isolatedProvider) {
        return properties.getPoolMode() == ExternalPoolMode.ISOLATED
                ? isolatedProvider
                : sharedProvider;
    }

    private WebClient buildClient(
            ExternalServiceProperties properties,
            ConnectionProvider provider,
            String baseUrl,
            DiagnosticProperties diagnosticProperties,
            String stage,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger,
            ExternalClientIdentityRegistry identityRegistry) {
        HttpClient httpClient = buildHttpClient(properties, provider, diagnosticProperties, stage,
                transportProperties, transportLogger);
        WebClient client = WebClient.builder()
                .defaultHeader("X-Experiment-Stage", stage)
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .baseUrl(baseUrl)
                .build();
        registerIdentity(identityRegistry, stage, client, httpClient, provider, baseUrl);
        return client;
    }

    private HttpClient buildHttpClient(
            ExternalServiceProperties properties,
            ConnectionProvider provider,
            DiagnosticProperties diagnosticProperties,
            String stage,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger) {
        HttpClient httpClient = HttpClient
                .create(provider)
                .option(
                        ChannelOption.CONNECT_TIMEOUT_MILLIS,
                        properties.getConnectTimeoutMs())
                .responseTimeout(Duration.ofMillis(
                        properties.getResponseTimeoutMs()));
        if (experimentMetricsEnabled || diagnosticProperties.isEnabled() || poolObservationEnabled) {
            httpClient = httpClient.metrics(true, uri -> uri);
        }
        httpClient = TransportHttpClientObservation.instrument(
                httpClient, stage, provider.name(), transportLogger,
                transportProperties.isEnabled());
        return httpClient;
    }

    private void registerIdentity(ExternalClientIdentityRegistry registry, String stage,
            WebClient client, HttpClient httpClient, ConnectionProvider provider, String baseUrl) {
        if (registry != null) {
            registry.register(stage, client, httpClient, provider, provider.name(), baseUrl);
        }
    }
}
