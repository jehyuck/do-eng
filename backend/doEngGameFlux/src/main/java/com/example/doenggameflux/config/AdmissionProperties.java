package com.example.doenggameflux.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.admission.ai")
@Getter
@Setter
public class AdmissionProperties {

    private boolean enabled = false;
    private int maxConcurrent = 320;
    private String mode = "FULL_PATH";

    public boolean isPerOutboundCall() {
        return "PER_OUTBOUND_CALL".equalsIgnoreCase(mode);
    }
}
