package com.example.doenggamemvc.experiment;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("experiment")
public class ExperimentPhaseTraceLogger {

    private static final Logger LOGGER =
            LoggerFactory.getLogger(ExperimentPhaseTraceLogger.class);
    private final ObjectMapper objectMapper;

    public ExperimentPhaseTraceLogger(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public void event(String event) {
        event(event, null);
    }

    public void event(String event, String outboundType) {
        ExperimentRequestTraceContext.TraceState state =
                ExperimentRequestTraceContext.current();
        if (state == null || !state.isSampled()) {
            return;
        }

        Map<String, Object> values = new LinkedHashMap<>();
        values.put("event", event);
        values.put("runId", state.getRunId());
        values.put("requestId", state.getRequestId());
        values.put("missionRunId", state.getMissionRunId());
        values.put("capturedAt", Instant.now().toString());
        values.put(
                "elapsedFromServerEnterMicros",
                (System.nanoTime() - state.getServerEnteredAtNs()) / 1_000L);
        values.put("thread", Thread.currentThread().getName());
        if (outboundType != null) {
            values.put("outboundType", outboundType);
        }

        try {
            LOGGER.info("DOENG_PHASE {}", objectMapper.writeValueAsString(values));
        } catch (JsonProcessingException error) {
            LOGGER.warn("Unable to serialize experiment phase trace", error);
        }
    }
}
