package com.example.doenggameflux.dispatcher;

import java.time.Duration;
import java.util.Objects;

public final class MissionExecutionContext {

    private final String requestId;
    private final long startedAtNanos;
    private final long deadlineNanos;

    private MissionExecutionContext(String requestId, long startedAtNanos, long deadlineNanos) {
        this.requestId = requestId;
        this.startedAtNanos = startedAtNanos;
        this.deadlineNanos = deadlineNanos;
    }

    public static MissionExecutionContext start(String requestId, Duration timeout) {
        Objects.requireNonNull(requestId, "requestId");
        Objects.requireNonNull(timeout, "timeout");
        if (timeout.isZero() || timeout.isNegative()) {
            throw new IllegalArgumentException("timeout must be positive");
        }
        long startedAt = System.nanoTime();
        return new MissionExecutionContext(
                requestId,
                startedAt,
                Math.addExact(startedAt, timeout.toNanos()));
    }

    public String getRequestId() {
        return requestId;
    }

    public Duration elapsed() {
        return Duration.ofNanos(Math.max(0L, System.nanoTime() - startedAtNanos));
    }

    public Duration remaining() {
        return Duration.ofNanos(Math.max(0L, deadlineNanos - System.nanoTime()));
    }

    public boolean isExpired() {
        return System.nanoTime() >= deadlineNanos;
    }
}
