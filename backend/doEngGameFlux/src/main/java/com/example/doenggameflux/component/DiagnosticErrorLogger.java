package com.example.doenggameflux.component;

import com.example.doenggameflux.config.DiagnosticProperties;
import com.example.doenggameflux.config.TransportAttributionProperties;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/** Observation-only error logging; it never consumes or transforms an error. */
@Component
@Slf4j
public class DiagnosticErrorLogger {

    private final DiagnosticProperties properties;
    private final TransportAttributionProperties transportProperties;

    public DiagnosticErrorLogger(
            DiagnosticProperties properties,
            TransportAttributionProperties transportProperties) {
        this.properties = properties;
        this.transportProperties = transportProperties;
    }

    public void log(String missionRunId, Throwable error) {
        if (!properties.isEnabled()) {
            return;
        }
        Throwable root = error;
        while (root.getCause() != null && root.getCause() != root) {
            root = root.getCause();
        }
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("diagnostic", true);
        event.put("timestamp", Instant.now().toString());
        event.put("missionRunId", missionRunId);
        event.put("stage", "UNKNOWN");
        event.put("throwableClass", error.getClass().getName());
        event.put("throwableMessage", error.getMessage());
        event.put("rootCauseClass", root.getClass().getName());
        event.put("rootCauseMessage", root.getMessage());
        event.put("thread", Thread.currentThread().getName());
        StringWriter stack = new StringWriter();
        error.printStackTrace(new PrintWriter(stack));
        event.put("stackTrace", stack.toString());
        log.error("DOENG_DIAGNOSTIC_ERROR {}", event);
    }

    public void logStageEvent(
            RequestIdentity identity,
            String stage,
            String eventName,
            Throwable error) {
        if (!transportProperties.isEnabled()) return;
        Throwable root = error == null ? null : rootCause(error);
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("stageDiagnostic", true);
        event.put("timestamp", Instant.now().toString());
        event.put("event", eventName);
        event.put("requestId", identity.getExperimentRequestId());
        event.put("runId", identity.getExperimentRunId());
        event.put("missionRunId", identity.getMissionRunId());
        event.put("stage", stage);
        event.put("throwableClass", error == null ? null : error.getClass().getName());
        event.put("throwableMessage", error == null ? null : error.getMessage());
        event.put("rootCauseClass", root == null ? null : root.getClass().getName());
        event.put("rootCauseMessage", root == null ? null : root.getMessage());
        event.put("stackTrace", error == null ? null : stackTrace(error));
        event.put("thread", Thread.currentThread().getName());
        log.info("DOENG_STAGE_EVENT {}", event);
    }

    private Throwable rootCause(Throwable error) {
        Throwable root = error;
        while (root.getCause() != null && root.getCause() != root) root = root.getCause();
        return root;
    }

    private String stackTrace(Throwable error) {
        StringWriter stack = new StringWriter();
        error.printStackTrace(new PrintWriter(stack));
        return stack.toString();
    }
}
