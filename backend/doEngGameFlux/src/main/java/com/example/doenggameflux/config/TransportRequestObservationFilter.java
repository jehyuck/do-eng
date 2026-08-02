package com.example.doenggameflux.config;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;
import reactor.core.publisher.Mono;
import reactor.core.publisher.SignalType;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
@RequiredArgsConstructor
@Slf4j
public class TransportRequestObservationFilter implements WebFilter {

    private static final String CONTEXT_KEY = TransportRequestObservationFilter.class.getName();
    private final TransportAttributionProperties properties;

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        if (!properties.isEnabled()) {
            return chain.filter(exchange);
        }
        String requestId = exchange.getRequest().getHeaders().getFirst("X-Experiment-Request-Id");
        if (requestId == null || requestId.isBlank()) {
            return chain.filter(exchange);
        }
        String runId = exchange.getRequest().getHeaders().getFirst("X-Experiment-Run-Id");
        String missionRunId = exchange.getRequest().getHeaders().getFirst("X-Mission-Run-Id");
        long started = System.nanoTime();
        event("RECEIVED", exchange, requestId, runId, missionRunId, null, started);
        return chain.filter(exchange)
                .doOnEach(signal -> {
                    if (signal.isOnComplete() || signal.isOnError() || signal.getType() == SignalType.CANCEL) {
                        event(signal.getType() == SignalType.CANCEL ? "CANCELLED" : "TERMINAL", exchange,
                                requestId, runId, missionRunId, signal.getThrowable(), started);
                    }
                })
                .contextWrite(context -> context
                        .put(CONTEXT_KEY, requestId)
                        .put("doeng.missionRunId", missionRunId == null ? "" : missionRunId));
    }

    private void event(String phase, ServerWebExchange exchange, String requestId, String runId,
                       String missionRunId, Throwable error, long started) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("transportDiagnostic", true);
        data.put("timestamp", Instant.now().toString());
        data.put("phase", phase);
        data.put("runId", runId);
        data.put("requestId", requestId);
        data.put("missionRunId", missionRunId);
        data.put("status", exchange.getResponse().getStatusCode() == null
                ? null : exchange.getResponse().getStatusCode().value());
        data.put("committed", exchange.getResponse().isCommitted());
        data.put("signalError", error == null ? null : error.getClass().getName());
        data.put("elapsedMs", TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started));
        data.put("thread", Thread.currentThread().getName());
        log.info("DOENG_INBOUND_EVENT {}", data);
    }
}
