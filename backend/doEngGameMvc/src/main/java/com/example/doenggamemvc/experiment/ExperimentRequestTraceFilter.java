package com.example.doenggamemvc.experiment;

import java.io.IOException;
import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Profile("experiment")
@Order(Ordered.HIGHEST_PRECEDENCE)
public class ExperimentRequestTraceFilter extends OncePerRequestFilter {

    private static final String RUN_ID_HEADER = "X-Experiment-Run-Id";
    private static final String REQUEST_ID_HEADER = "X-Experiment-Request-Id";
    private static final String MISSION_RUN_ID_HEADER = "X-Mission-Run-Id";

    private final ExperimentPhaseTraceLogger traceLogger;

    public ExperimentRequestTraceFilter(ExperimentPhaseTraceLogger traceLogger) {
        this.traceLogger = traceLogger;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain)
            throws ServletException, IOException {
        if (!"POST".equalsIgnoreCase(request.getMethod())
                || !"/game/face".equals(request.getRequestURI())) {
            filterChain.doFilter(request, response);
            return;
        }

        String requestId = request.getHeader(REQUEST_ID_HEADER);
        if (!StringUtils.hasText(requestId)) {
            filterChain.doFilter(request, response);
            return;
        }

        ExperimentRequestTraceContext.install(
                request.getHeader(RUN_ID_HEADER),
                requestId,
                request.getHeader(MISSION_RUN_ID_HEADER));
        try {
            traceLogger.event("SERVER_ENTER");
            filterChain.doFilter(request, response);
        } finally {
            try {
                traceLogger.event("SERVER_EXIT");
            } finally {
                ExperimentRequestTraceContext.clear();
            }
        }
    }
}
