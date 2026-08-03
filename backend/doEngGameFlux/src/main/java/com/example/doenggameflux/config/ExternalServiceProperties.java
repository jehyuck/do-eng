package com.example.doenggameflux.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "doeng.external")
@Getter
@Setter
public class ExternalServiceProperties {

    private String aiBaseUrl = "https://j8a601.p.ssafy.io/analyze";
    private String tokenVerificationUrl = "https://j8a601.p.ssafy.io/api/member/ai";
    private String storageBaseUrl = "http://localhost:9100";
    /** @deprecated use sharedPool.maxConnections and the explicit pool mode. */
    @Deprecated
    private int maxConnections = 200;
    private int connectTimeoutMs = 2000;
    private int responseTimeoutMs = 10000;
    private int pendingAcquireTimeoutMs = 10000;
    private long maxIdleTimeMs = 0;
    private ExternalLeasingStrategy leasingStrategy = ExternalLeasingStrategy.FIFO;
    private long backgroundEvictionIntervalMs = 0;
    private ExternalPoolMode poolMode = ExternalPoolMode.SHARED;
    private PoolSettings sharedPool = new PoolSettings(200, 400);
    private PoolSettings tokenPool = new PoolSettings(40, 80);
    private PoolSettings aiPool = new PoolSettings(320, 640);
    private PoolSettings storagePool = new PoolSettings(40, 80);

    public void validatePoolContract() {
        if (leasingStrategy == null) {
            throw new IllegalStateException("leasing-strategy must not be null");
        }
        if (maxIdleTimeMs < 0) {
            throw new IllegalStateException("max-idle-time-ms must be zero or positive");
        }
        if (backgroundEvictionIntervalMs < 0) {
            throw new IllegalStateException("eviction-interval-ms must be zero or positive");
        }
        validateSettings("shared-pool", sharedPool);
        validateSettings("token-pool", tokenPool);
        validateSettings("ai-pool", aiPool);
        validateSettings("storage-pool", storagePool);
        if (poolMode == ExternalPoolMode.ISOLATED) {
            int activeTotal = tokenPool.getMaxConnections()
                    + aiPool.getMaxConnections()
                    + storagePool.getMaxConnections();
            int pendingTotal = tokenPool.getPendingAcquireMaxCount()
                    + aiPool.getPendingAcquireMaxCount()
                    + storagePool.getPendingAcquireMaxCount();
            if (activeTotal != sharedPool.getMaxConnections()
                    || pendingTotal != sharedPool.getPendingAcquireMaxCount()) {
                throw new IllegalStateException(
                        "ISOLATED pool budgets must equal SHARED budget: active "
                                + activeTotal + " != " + sharedPool.getMaxConnections()
                                + " or pending " + pendingTotal + " != "
                                + sharedPool.getPendingAcquireMaxCount());
            }
        }
    }

    private void validateSettings(String name, PoolSettings settings) {
        if (settings == null
                || settings.getMaxConnections() <= 0
                || settings.getPendingAcquireMaxCount() <= 0) {
            throw new IllegalStateException(
                    name + " max-connections and pending-acquire-max-count must be positive");
        }
    }

    @Getter
    @Setter
    public static class PoolSettings {
        private int maxConnections;
        private int pendingAcquireMaxCount;

        public PoolSettings() {
        }

        public PoolSettings(int maxConnections, int pendingAcquireMaxCount) {
            this.maxConnections = maxConnections;
            this.pendingAcquireMaxCount = pendingAcquireMaxCount;
        }
    }
}
