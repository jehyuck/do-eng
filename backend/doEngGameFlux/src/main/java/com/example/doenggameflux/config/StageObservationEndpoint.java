package com.example.doenggameflux.config;

import com.example.doenggameflux.component.StageObservation;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@Endpoint(id = "doengstages")
@ConditionalOnProperty(name = "doeng.stage-observation.enabled", havingValue = "true")
public class StageObservationEndpoint {

    private final StageObservation observation;

    public StageObservationEndpoint(StageObservation observation) {
        this.observation = observation;
    }

    @ReadOperation
    public Map<String, Object> snapshot() {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("capturedAtEpochMs", System.currentTimeMillis());
        response.put("stages", observation.snapshot());
        return response;
    }
}
