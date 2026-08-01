package com.example.doenggameflux.config;

import com.example.doenggameflux.component.AiOutboundAdmissionGate;
import java.util.Map;
import org.springframework.boot.actuate.endpoint.annotation.Endpoint;
import org.springframework.boot.actuate.endpoint.annotation.ReadOperation;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@Endpoint(id = "doengadmission")
@ConditionalOnProperty(name = "doeng.admission.ai.enabled", havingValue = "true")
public class AdmissionEndpoint {

    private final AiOutboundAdmissionGate gate;

    public AdmissionEndpoint(AiOutboundAdmissionGate gate) {
        this.gate = gate;
    }

    @ReadOperation
    public Map<String, Object> snapshot() {
        return Map.of("capturedAtEpochMs", System.currentTimeMillis(),
                "mode", gate.isPerOutboundCall() ? "PER_OUTBOUND_CALL" : "FULL_PATH",
                "admission", gate.snapshot(), "stages", gate.stageSnapshot());
    }
}
