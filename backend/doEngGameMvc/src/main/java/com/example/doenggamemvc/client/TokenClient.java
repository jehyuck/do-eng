package com.example.doenggamemvc.client;

import com.example.doenggamemvc.config.ExternalServiceProperties;
import com.example.doenggamemvc.dto.TokenResponse;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Component
public class TokenClient {

    private final RestTemplate restTemplate;
    private final String tokenVerificationUrl;

    public TokenClient(
            RestTemplate externalRestTemplate,
            ExternalServiceProperties properties) {
        this.restTemplate = externalRestTemplate;
        this.tokenVerificationUrl = properties.getTokenVerificationUrl();
    }

    public long confirm(String authorization) {
        HttpHeaders headers = new HttpHeaders();
        headers.set(HttpHeaders.AUTHORIZATION, authorization);

        ResponseEntity<TokenResponse> response = restTemplate.exchange(
                tokenVerificationUrl,
                HttpMethod.GET,
                new HttpEntity<>(headers),
                TokenResponse.class);

        TokenResponse body = response.getBody();
        if (body == null) {
            throw new IllegalStateException("Token response body is empty");
        }
        return body.getId();
    }
}
