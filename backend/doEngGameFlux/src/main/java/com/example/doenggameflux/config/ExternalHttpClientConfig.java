package com.example.doenggameflux.config;

import io.netty.channel.ChannelOption;
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
            @Qualifier("tokenConnectionProvider") ConnectionProvider provider,
            DiagnosticProperties diagnosticProperties) {
        return buildClient(properties, provider, properties.getTokenVerificationUrl(), diagnosticProperties);
    }

    @Bean("aiWebClient")
    public WebClient aiWebClient(
            ExternalServiceProperties properties,
            @Qualifier("aiConnectionProvider") ConnectionProvider provider,
            DiagnosticProperties diagnosticProperties) {
        WebClient.Builder builder = buildClientBuilder(properties, provider, diagnosticProperties);
        return builder
                .baseUrl(properties.getAiBaseUrl())
                .codecs(configurer ->
                        configurer.defaultCodecs().maxInMemorySize(2 * 1024 * 1024))
                .build();
    }

    @Bean("storageWebClient")
    public WebClient storageWebClient(
            ExternalServiceProperties properties,
            @Qualifier("storageConnectionProvider") ConnectionProvider provider,
            DiagnosticProperties diagnosticProperties) {
        return buildClient(properties, provider, properties.getStorageBaseUrl(), diagnosticProperties);
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
        if (experimentMetricsEnabled || diagnosticProperties.isEnabled() || poolObservationEnabled) {
            builder.metrics(true);
        }
        return builder.build();
    }

    private WebClient buildClient(
            ExternalServiceProperties properties,
            ConnectionProvider provider,
            String baseUrl,
            DiagnosticProperties diagnosticProperties) {
        return buildClientBuilder(properties, provider, diagnosticProperties)
                .baseUrl(baseUrl)
                .build();
    }

    private WebClient.Builder buildClientBuilder(
            ExternalServiceProperties properties,
            ConnectionProvider provider,
            DiagnosticProperties diagnosticProperties) {
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
        return WebClient.builder()
                .clientConnector(new ReactorClientHttpConnector(httpClient));
    }
}
