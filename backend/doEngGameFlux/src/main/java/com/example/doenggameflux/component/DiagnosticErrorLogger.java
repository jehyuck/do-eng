package com.example.doenggameflux.component;

import com.example.doenggameflux.config.DiagnosticProperties;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/** Observation-only error logging; it never consumes or transforms an error. */
@Component
@RequiredArgsConstructor
@Slf4j
public class DiagnosticErrorLogger {

    private final DiagnosticProperties properties;

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
}
