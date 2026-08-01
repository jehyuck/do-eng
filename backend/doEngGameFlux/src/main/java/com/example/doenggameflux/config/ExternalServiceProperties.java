package com.example.doenggameflux.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.external")
@Getter
@Setter
public class ExternalServiceProperties {

    private String aiBaseUrl = "https://j8a601.p.ssafy.io/analyze";
    private String tokenVerificationUrl = "https://j8a601.p.ssafy.io/api/member/ai";
    private String storageBaseUrl = "http://localhost:9100";
    private int maxConnections = 200;
    private int connectTimeoutMs = 2000;
    private int responseTimeoutMs = 10000;
    private int pendingAcquireTimeoutMs = 10000;
}
