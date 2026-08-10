package com.example.doenggamemvc.config;

import java.io.IOException;
import java.util.concurrent.TimeUnit;
import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
public class ExperimentRequestLoggingFilter extends OncePerRequestFilter {

    private static final Logger LOGGER =
            LoggerFactory.getLogger(ExperimentRequestLoggingFilter.class);
    private static final String RUN_ID_HEADER = "X-Experiment-Run-Id";
    private static final String REQUEST_ID_HEADER = "X-Experiment-Request-Id";

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain)
            throws ServletException, IOException {
        String runId = request.getHeader(RUN_ID_HEADER);
        if (runId == null || runId.isBlank()) {
            filterChain.doFilter(request, response);
            return;
        }

        String requestId = request.getHeader(REQUEST_ID_HEADER);
        if (requestId == null || requestId.isBlank()) {
            requestId = "mvc-" + System.nanoTime();
        }

        response.setHeader(RUN_ID_HEADER, runId);
        response.setHeader(REQUEST_ID_HEADER, requestId);
        long startedAt = System.nanoTime();

        try {
            filterChain.doFilter(request, response);
        } finally {
            long latencyMs = TimeUnit.NANOSECONDS.toMillis(
                    System.nanoTime() - startedAt);
            LOGGER.info(
                    "experiment_request runId={} requestId={} method={} path={} status={} latencyMs={}",
                    runId,
                    requestId,
                    request.getMethod(),
                    request.getRequestURI(),
                    response.getStatus(),
                    latencyMs);
        }
    }
}
