package com.example.doenggameflux.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.admission.ai")
public class AdmissionProperties {

    /** Legacy switch retained so old experiment overlays remain readable. */
    private boolean enabled = false;
    private int maxConcurrent = 320;
    private AdmissionMode mode = AdmissionMode.OFF;
    private AdmissionScope scope = AdmissionScope.FULL_PATH;

    public boolean isEnabled() {
        return resolvedMode() != AdmissionMode.OFF;
    }

    public AdmissionMode resolvedMode() {
        if (mode != AdmissionMode.OFF) {
            return mode;
        }
        // Existing 1-3/1-5 overlays only supplied enabled=true. Preserve
        // their behavior while new runs use the explicit enum mode.
        return enabled ? AdmissionMode.ENFORCE : AdmissionMode.OFF;
    }

    public boolean isPerOutboundCall() {
        return scope == AdmissionScope.PER_OUTBOUND_CALL;
    }

    public boolean isFullPath() {
        return scope == AdmissionScope.FULL_PATH;
    }

    public boolean isEnabledLegacy() {
        return enabled;
    }

    public boolean isEnabledForRequest() {
        return isEnabled();
    }

    public boolean isEnabledFlag() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public int getMaxConcurrent() {
        return maxConcurrent;
    }

    public void setMaxConcurrent(int maxConcurrent) {
        if (maxConcurrent < 1) {
            throw new IllegalArgumentException("maxConcurrent must be positive");
        }
        this.maxConcurrent = maxConcurrent;
    }

    public AdmissionMode getMode() {
        return mode;
    }

    public void setMode(AdmissionMode mode) {
        this.mode = mode == null ? AdmissionMode.OFF : mode;
    }

    public AdmissionScope getScope() {
        return scope;
    }

    public void setScope(AdmissionScope scope) {
        this.scope = scope == null ? AdmissionScope.FULL_PATH : scope;
    }
}
