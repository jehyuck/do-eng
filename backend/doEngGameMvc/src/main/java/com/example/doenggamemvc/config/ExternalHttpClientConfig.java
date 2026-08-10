package com.example.doenggamemvc.config;

import org.apache.http.client.config.RequestConfig;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.apache.http.impl.conn.PoolingHttpClientConnectionManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

@Configuration
public class ExternalHttpClientConfig {

    @Bean(destroyMethod = "close")
    public CloseableHttpClient externalHttpClient(
            ExternalServiceProperties properties,
            PoolingHttpClientConnectionManager externalHttpConnectionManager) {
        RequestConfig requestConfig = RequestConfig.custom()
                .setConnectTimeout(properties.getConnectTimeoutMs())
                .setSocketTimeout(properties.getResponseTimeoutMs())
                .setConnectionRequestTimeout(
                        properties.getPendingAcquireTimeoutMs())
                .build();

        return HttpClientBuilder.create()
                .setConnectionManager(externalHttpConnectionManager)
                .setDefaultRequestConfig(requestConfig)
                .disableCookieManagement()
                .build();
    }

    @Bean(destroyMethod = "shutdown")
    public PoolingHttpClientConnectionManager externalHttpConnectionManager(
            ExternalServiceProperties properties) {
        PoolingHttpClientConnectionManager connectionManager =
                new PoolingHttpClientConnectionManager();
        connectionManager.setMaxTotal(properties.getMaxConnections());
        connectionManager.setDefaultMaxPerRoute(properties.getMaxConnections());
        return connectionManager;
    }

    @Bean
    public RestTemplate externalRestTemplate(
            CloseableHttpClient externalHttpClient) {
        return new RestTemplate(
                new HttpComponentsClientHttpRequestFactory(externalHttpClient));
    }
}
