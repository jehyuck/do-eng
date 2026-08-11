package com.example.doenggamemvc.experiment;

import java.io.IOException;
import java.net.URI;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpRequest;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.stereotype.Component;

@Component
@Profile("experiment")
public class ExperimentRestTemplateTraceInterceptor
        implements ClientHttpRequestInterceptor {

    private static final String RUN_ID_HEADER = "X-Experiment-Run-Id";
    private static final String REQUEST_ID_HEADER = "X-Experiment-Request-Id";
    private static final String MISSION_RUN_ID_HEADER = "X-Mission-Run-Id";

    private final ExperimentPhaseTraceLogger traceLogger;

    public ExperimentRestTemplateTraceInterceptor(
            ExperimentPhaseTraceLogger traceLogger) {
        this.traceLogger = traceLogger;
    }

    @Override
    public ClientHttpResponse intercept(
            HttpRequest request,
            byte[] body,
            ClientHttpRequestExecution execution)
            throws IOException {
        String outboundType = classify(request.getURI());
        ExperimentRequestTraceContext.TraceState state =
                ExperimentRequestTraceContext.current();
        if (state == null || outboundType == null) {
            return execution.execute(request, body);
        }

        if (state.getRunId() != null) {
            request.getHeaders().set(RUN_ID_HEADER, state.getRunId());
        }
        request.getHeaders().set(REQUEST_ID_HEADER, state.getRequestId());
        if (state.getMissionRunId() != null) {
            request.getHeaders().set(MISSION_RUN_ID_HEADER, state.getMissionRunId());
        }
        traceLogger.event(outboundType + "_HTTP_START", outboundType);
        try {
            ClientHttpResponse response = execution.execute(request, body);
            traceLogger.event(outboundType + "_HTTP_END", outboundType);
            return response;
        } catch (IOException | RuntimeException error) {
            traceLogger.event(outboundType + "_HTTP_ERROR", outboundType);
            throw error;
        }
    }

    private String classify(URI uri) {
        String path = uri.getPath();
        if (path == null) {
            return null;
        }
        if (path.endsWith("/api/member/ai")) {
            return "TOKEN";
        }
        if (path.endsWith("/face")) {
            return "AI";
        }
        if (path.endsWith("/storage/object")) {
            return "STORAGE";
        }
        return null;
    }
}
