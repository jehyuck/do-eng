package com.example.doenggameflux.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestSizeLimitFilter implements WebFilter {

    private final long maxRequestBytes;

    public RequestSizeLimitFilter(
            @Value("${doeng.mission.max-request-bytes:2097152}")
            long maxRequestBytes) {
        this.maxRequestBytes = maxRequestBytes;
    }

    @Override
    public Mono<Void> filter(
            ServerWebExchange exchange,
            WebFilterChain chain) {
        long contentLength = exchange.getRequest()
                .getHeaders()
                .getContentLength();

        if (contentLength > maxRequestBytes) {
            exchange.getResponse().setStatusCode(HttpStatus.PAYLOAD_TOO_LARGE);
            return exchange.getResponse().setComplete();
        }

        return chain.filter(exchange);
    }
}
