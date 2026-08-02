package com.example.doenggameflux.component;

import com.example.doenggameflux.config.StageObservationProperties;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.LongAdder;
import org.springframework.stereotype.Component;
import org.springframework.beans.factory.annotation.Autowired;
import reactor.core.publisher.Mono;

/** Low-overhead, opt-in stage counters. It never changes publisher semantics. */
@Component
public class StageObservation {

    private final StageObservationProperties properties;
    private final DiagnosticErrorLogger diagnosticLogger;
    private final Map<String, StageStats> stages = new ConcurrentHashMap<>();

    @Autowired
    public StageObservation(
            StageObservationProperties properties,
            DiagnosticErrorLogger diagnosticLogger) {
        this.properties = properties;
        this.diagnosticLogger = diagnosticLogger;
    }

    public StageObservation(StageObservationProperties properties) {
        this(properties, new DiagnosticErrorLogger(
                new com.example.doenggameflux.config.DiagnosticProperties(),
                new com.example.doenggameflux.config.TransportAttributionProperties()));
    }

    public <T> Mono<T> observe(String stage, Mono<T> source) {
        if (!properties.isEnabled()) {
            return source;
        }
        StageStats stats = stages.computeIfAbsent(stage, ignored -> new StageStats());
        return Mono.deferContextual(contextView -> {
            RequestIdentity identity = RequestIdentity.from(contextView);
            AtomicLong subscriptionStartedAt = new AtomicLong();
            return Mono.defer(() -> source)
                    .doOnSubscribe(ignored -> {
                        subscriptionStartedAt.set(System.nanoTime());
                        stats.started.increment();
                        int current = stats.inFlight.incrementAndGet();
                        stats.maxInFlight.accumulateAndGet(current, Math::max);
                        stats.lastThread = Thread.currentThread().getName();
                        diagnosticLogger.logStageEvent(identity, stage, "STAGE_STARTED", null);
                    })
                    .doOnSuccess(value -> {
                        stats.succeeded.increment();
                        diagnosticLogger.logStageEvent(identity, stage, "STAGE_SUCCEEDED", null);
                    })
                    .doOnError(error -> {
                        stats.failed.increment();
                        diagnosticLogger.logStageEvent(identity, stage, "STAGE_FAILED", error);
                    })
                    .doFinally(signal -> {
                        long started = subscriptionStartedAt.get();
                        if (started != 0) stats.durationNanos.add(System.nanoTime() - started);
                        stats.inFlight.decrementAndGet();
                        if (signal == reactor.core.publisher.SignalType.CANCEL) {
                            stats.cancelled.increment();
                            diagnosticLogger.logStageEvent(identity, stage, "STAGE_CANCELLED", null);
                        }
                        diagnosticLogger.logStageEvent(identity, stage, "STAGE_TERMINATED", null);
                    });
        });
    }

    public List<Map<String, Object>> snapshot() {
        List<Map<String, Object>> result = new ArrayList<>();
        stages.forEach((stage, stats) -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("stage", stage);
            row.put("capturedAt", Instant.now().toString());
            row.put("started", stats.started.sum());
            row.put("succeeded", stats.succeeded.sum());
            row.put("failed", stats.failed.sum());
            row.put("cancelled", stats.cancelled.sum());
            row.put("inFlight", stats.inFlight.get());
            row.put("maxInFlight", stats.maxInFlight.get());
            row.put("durationMsTotal", stats.durationNanos.sum() / 1_000_000.0);
            row.put("lastThread", stats.lastThread);
            result.add(row);
        });
        return result;
    }

    private static final class StageStats {
        private final LongAdder started = new LongAdder();
        private final LongAdder succeeded = new LongAdder();
        private final LongAdder failed = new LongAdder();
        private final LongAdder cancelled = new LongAdder();
        private final LongAdder durationNanos = new LongAdder();
        private final AtomicInteger inFlight = new AtomicInteger();
        private final AtomicInteger maxInFlight = new AtomicInteger();
        private volatile String lastThread = "";
    }
}
