package com.example.doenggamemvc.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.external")
public class ExternalServiceProperties {

    private String aiBaseUrl = "https://j8a601.p.ssafy.io/analyze";
    private String tokenVerificationUrl = "https://j8a601.p.ssafy.io/api/member/ai";
    private String storageBaseUrl = "http://localhost:9100";
    private int maxConnections = 200;
    private int connectTimeoutMs = 2000;
    private int responseTimeoutMs = 10000;
    private int pendingAcquireTimeoutMs = 10000;

    public String getAiBaseUrl() {
        return aiBaseUrl;
    }

    public void setAiBaseUrl(String aiBaseUrl) {
        this.aiBaseUrl = aiBaseUrl;
    }

    public String getTokenVerificationUrl() {
        return tokenVerificationUrl;
    }

    public void setTokenVerificationUrl(String tokenVerificationUrl) {
        this.tokenVerificationUrl = tokenVerificationUrl;
    }

    public String getStorageBaseUrl() {
        return storageBaseUrl;
    }

    public void setStorageBaseUrl(String storageBaseUrl) {
        this.storageBaseUrl = storageBaseUrl;
    }

    public int getMaxConnections() {
        return maxConnections;
    }

    public void setMaxConnections(int maxConnections) {
        this.maxConnections = maxConnections;
    }

    public int getConnectTimeoutMs() {
        return connectTimeoutMs;
    }

    public void setConnectTimeoutMs(int connectTimeoutMs) {
        this.connectTimeoutMs = connectTimeoutMs;
    }

    public int getResponseTimeoutMs() {
        return responseTimeoutMs;
    }

    public void setResponseTimeoutMs(int responseTimeoutMs) {
        this.responseTimeoutMs = responseTimeoutMs;
    }

    public int getPendingAcquireTimeoutMs() {
        return pendingAcquireTimeoutMs;
    }

    public void setPendingAcquireTimeoutMs(int pendingAcquireTimeoutMs) {
        this.pendingAcquireTimeoutMs = pendingAcquireTimeoutMs;
    }
}
