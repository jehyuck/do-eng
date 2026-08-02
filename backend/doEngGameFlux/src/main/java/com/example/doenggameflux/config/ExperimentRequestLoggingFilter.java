package com.example.doenggameflux.config;

import com.example.doenggameflux.component.RequestIdentity;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;

@Component
@Slf4j
public class ExperimentRequestLoggingFilter implements WebFilter {

    public static final String RUN_ID_HEADER = RequestIdentity.EXPERIMENT_RUN_ID_HEADER;
    public static final String REQUEST_ID_HEADER = RequestIdentity.EXPERIMENT_REQUEST_ID_HEADER;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        String runId = exchange.getRequest().getHeaders().getFirst(RUN_ID_HEADER);
        if (runId == null || runId.isBlank()) {
            return chain.filter(exchange);
        }

        String requestId = exchange.getRequest().getHeaders().getFirst(REQUEST_ID_HEADER);
        if (requestId == null || requestId.isBlank()) {
            requestId = exchange.getRequest().getId();
        }

        String finalRequestId = requestId;
        long startedAt = System.nanoTime();
        exchange.getResponse().getHeaders().set(RUN_ID_HEADER, runId);
        exchange.getResponse().getHeaders().set(REQUEST_ID_HEADER, requestId);

        return chain.filter(exchange)
                .doFinally(signalType -> {
                    HttpStatus status = exchange.getResponse().getStatusCode();
                    long latencyMs = TimeUnit.NANOSECONDS.toMillis(
                            System.nanoTime() - startedAt);
                    log.info(
                            "experiment_request runId={} requestId={} method={} path={} status={} signal={} latencyMs={}",
                            runId,
                            finalRequestId,
                            exchange.getRequest().getMethodValue(),
                            exchange.getRequest().getPath().value(),
                            status == null ? "uncommitted" : status.value(),
                            signalType,
                            latencyMs);
                });
    }
}
