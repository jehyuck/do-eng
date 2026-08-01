package com.example.doenggameflux.config;

import io.netty.channel.ChannelOption;
import java.time.Duration;
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

    @Bean(destroyMethod = "dispose")
    public ConnectionProvider externalConnectionProvider(
            ExternalServiceProperties properties,
            DiagnosticProperties diagnosticProperties) {
        ConnectionProvider.Builder builder = ConnectionProvider.builder("doeng-external")
                .maxConnections(properties.getMaxConnections())
                .pendingAcquireTimeout(Duration.ofMillis(
                        properties.getPendingAcquireTimeoutMs()));
        if (experimentMetricsEnabled || diagnosticProperties.isEnabled() || poolObservationEnabled) {
            builder.metrics(true);
        }
        return builder.build();
    }

    @Bean("externalWebClientBuilder")
    public WebClient.Builder externalWebClientBuilder(
            ExternalServiceProperties properties,
            ConnectionProvider externalConnectionProvider,
            DiagnosticProperties diagnosticProperties) {
        HttpClient httpClient = HttpClient
                .create(externalConnectionProvider)
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
