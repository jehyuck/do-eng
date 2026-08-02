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
                transportProperties, new TransportDiagnosticLogger(transportProperties));
    }

    public WebClient aiWebClient(
            ExternalServiceProperties properties,
            ConnectionProvider sharedProvider,
            ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties) {
        TransportAttributionProperties transportProperties = new TransportAttributionProperties();
        return aiWebClient(properties, sharedProvider, isolatedProvider, diagnosticProperties,
                transportProperties, new TransportDiagnosticLogger(transportProperties));
    }

    public WebClient storageWebClient(
            ExternalServiceProperties properties,
            ConnectionProvider sharedProvider,
            ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties) {
        TransportAttributionProperties transportProperties = new TransportAttributionProperties();
        return storageWebClient(properties, sharedProvider, isolatedProvider, diagnosticProperties,
                transportProperties, new TransportDiagnosticLogger(transportProperties));
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
            TransportDiagnosticLogger transportLogger) {
        return buildClient(properties, selectProvider(properties, sharedProvider, isolatedProvider),
                properties.getTokenVerificationUrl(), diagnosticProperties, "TOKEN",
                transportProperties, transportLogger);
    }

    @Bean("aiWebClient")
    public WebClient aiWebClient(
            ExternalServiceProperties properties,
            @Qualifier("sharedConnectionProvider") ConnectionProvider sharedProvider,
            @Qualifier("aiConnectionProvider") ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger) {
        WebClient.Builder builder = buildClientBuilder(
                properties,
                selectProvider(properties, sharedProvider, isolatedProvider),
                diagnosticProperties, "AI", transportProperties, transportLogger);
        return builder
                .baseUrl(properties.getAiBaseUrl())
                .codecs(configurer ->
                        configurer.defaultCodecs().maxInMemorySize(2 * 1024 * 1024))
                .build();
    }

    @Bean("storageWebClient")
    public WebClient storageWebClient(
            ExternalServiceProperties properties,
            @Qualifier("sharedConnectionProvider") ConnectionProvider sharedProvider,
            @Qualifier("storageConnectionProvider") ConnectionProvider isolatedProvider,
            DiagnosticProperties diagnosticProperties,
            TransportAttributionProperties transportProperties,
            TransportDiagnosticLogger transportLogger) {
        return buildClient(properties, selectProvider(properties, sharedProvider, isolatedProvider),
                properties.getStorageBaseUrl(), diagnosticProperties, "STORAGE",
                transportProperties, transportLogger);
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
        if (properties.getMaxIdleTimeMs() > 0) {
            builder.maxIdleTime(Duration.ofMillis(properties.getMaxIdleTimeMs()));
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
            TransportDiagnosticLogger transportLogger) {
        return buildClientBuilder(properties, provider, diagnosticProperties, stage,
                transportProperties, transportLogger)
                .baseUrl(baseUrl)
                .build();
    }

    private WebClient.Builder buildClientBuilder(
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
        return WebClient.builder()
                .defaultHeader("X-Experiment-Stage", stage)
                .clientConnector(new ReactorClientHttpConnector(httpClient));
    }
}
