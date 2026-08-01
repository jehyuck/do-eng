package com.example.doenggameflux.component;

import com.example.doenggameflux.config.ExternalServiceProperties;
import com.example.doenggameflux.dto.response.TokenResponseDto;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;


@Component
public class TokenComponent {
    private final WebClient webClient;

    public TokenComponent(
            ExternalServiceProperties properties,
            @Qualifier("externalWebClientBuilder")
            WebClient.Builder externalWebClientBuilder) {
        this.webClient = externalWebClientBuilder.clone()
                .baseUrl(properties.getTokenVerificationUrl())
                .build();
    }

    public Mono<Long> jwtConfirm(String authorization) {
        return webClient
                .get()
                .header(HttpHeaders.AUTHORIZATION, authorization)
                .retrieve()
                .bodyToMono(TokenResponseDto.class)
                .map(TokenResponseDto::getId);
    }
}
