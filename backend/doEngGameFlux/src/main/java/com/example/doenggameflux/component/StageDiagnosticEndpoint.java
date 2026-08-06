package com.example.doenggameflux.component;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.stereotype.Component;

@Component
@Endpoint(id = "doengdiagnosticstage")
public class StageDiagnosticEndpoint {

    private final StageObservation stageObservation;

    public StageDiagnosticEndpoint(StageObservation stageObservation) {
        this.stageObservation = stageObservation;
    }

    @ReadOperation
    public Map<String, Object> snapshot() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("capturedAt", Instant.now().toString());
        result.put("stages", stageObservation.snapshot());
        return result;
    }
}
