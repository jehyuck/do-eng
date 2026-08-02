package com.example.doenggameflux.component;

import com.example.doenggameflux.config.TransportAttributionProperties;
import java.net.SocketAddress;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/** Bounded, observation-only transport events. No request body or credentials are logged. */
@Component
@RequiredArgsConstructor
@Slf4j
public class TransportDiagnosticLogger {

    private final TransportAttributionProperties properties;

    public void log(
            String stage,
            String phase,
            String requestId,
            String missionRunId,
            Throwable error,
            SocketAddress remoteAddress,
            long elapsedMs,
            String thread,
            String category) {
        if (!properties.isEnabled()) {
            return;
        }
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("transportDiagnostic", true);
        event.put("timestamp", Instant.now().toString());
        event.put("stage", stage);
        event.put("phase", phase);
        event.put("requestId", requestId);
        event.put("missionRunId", missionRunId);
        event.put("category", category);
        event.put("throwableClass", error == null ? null : error.getClass().getName());
        event.put("throwableMessage", error == null ? null : error.getMessage());
        event.put("rootCauseClass", error == null ? null : rootCause(error).getClass().getName());
        event.put("rootCauseMessage", error == null ? null : rootCause(error).getMessage());
        event.put("remoteAddress", remoteAddress == null ? null : remoteAddress.toString());
        event.put("thread", thread);
        event.put("elapsedMs", elapsedMs);
        log.warn("DOENG_TRANSPORT_EVENT {}", event);
    }

    public void logState(String stage, String state, SocketAddress remoteAddress, String thread) {
        if (!properties.isEnabled()) {
            return;
        }
        Map<String, Object> event = new LinkedHashMap<>();
        event.put("transportDiagnostic", true);
        event.put("timestamp", Instant.now().toString());
        event.put("stage", stage);
        event.put("phase", "CONNECTION_STATE");
        event.put("state", state);
        event.put("remoteAddress", remoteAddress == null ? null : remoteAddress.toString());
        event.put("thread", thread);
        log.info("DOENG_TRANSPORT_EVENT {}", event);
    }

    private Throwable rootCause(Throwable error) {
        Throwable root = error;
        int depth = 0;
        while (root.getCause() != null && root.getCause() != root && depth++ < 3) {
            root = root.getCause();
        }
        return root;
    }
}
