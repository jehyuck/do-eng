package com.example.doenggameflux.component;

import com.example.doenggameflux.config.AdmissionProperties;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.Supplier;
import java.util.EnumMap;
import java.util.Map;
import lombok.Getter;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
public class AiOutboundAdmissionGate {

    private final AdmissionProperties properties;
    private final AtomicInteger inUse = new AtomicInteger();
    private final AtomicInteger maxObserved = new AtomicInteger();
    private final LongAdder acquired = new LongAdder();
    private final LongAdder rejected = new LongAdder();
    private final LongAdder released = new LongAdder();
    private final Counter acquiredCounter;
    private final Counter rejectedCounter;
    private final Counter releasedCounter;
    private final Map<OutboundStage, StageCounters> stageCounters = new EnumMap<>(OutboundStage.class);

    public AiOutboundAdmissionGate(
            AdmissionProperties properties,
            MeterRegistry registry) {
        this.properties = properties;
        Gauge.builder("doeng.ai.admission.in_use", inUse, AtomicInteger::get)
                .register(registry);
        Gauge.builder("doeng.ai.admission.max_observed", maxObserved, AtomicInteger::get)
                .register(registry);
        Gauge.builder("doeng.ai.admission.limit", properties, p -> p.getMaxConcurrent())
                .register(registry);
        this.acquiredCounter = Counter.builder("doeng.ai.admission.acquired").register(registry);
        this.rejectedCounter = Counter.builder("doeng.ai.admission.rejected").register(registry);
        this.releasedCounter = Counter.builder("doeng.ai.admission.released").register(registry);
        for (OutboundStage stage : OutboundStage.values()) stageCounters.put(stage, new StageCounters());
    }

    public <T> Mono<T> execute(Supplier<Mono<T>> action) {
        return execute(null, action);
    }

    public <T> Mono<T> execute(OutboundStage stage, Supplier<Mono<T>> action) {
        return Mono.defer(() -> {
            if (!properties.isEnabled()) {
                return action.get();
            }
            if (!tryAcquire()) {
                if (stage != null) stageCounters.get(stage).rejected.increment();
                rejected.increment();
                rejectedCounter.increment();
                return Mono.error(new AiCapacityExceededException());
            }
            if (stage != null) stageCounters.get(stage).acquired.increment();
            return action.get().doFinally(signal -> release(stage));
        });
    }

    public <T> Mono<T> executeStage(OutboundStage stage, Supplier<Mono<T>> action) {
        return properties.isPerOutboundCall() ? execute(stage, action) : action.get();
    }

    public boolean isPerOutboundCall() {
        return properties.isPerOutboundCall();
    }

    private boolean tryAcquire() {
        while (true) {
            int current = inUse.get();
            if (current >= properties.getMaxConcurrent()) {
                return false;
            }
            if (inUse.compareAndSet(current, current + 1)) {
                acquired.increment();
                acquiredCounter.increment();
                maxObserved.accumulateAndGet(current + 1, Math::max);
                return true;
            }
        }
    }

    private void release(OutboundStage stage) {
        inUse.decrementAndGet();
        released.increment();
        releasedCounter.increment();
        if (stage != null) stageCounters.get(stage).released.increment();
    }

    public Snapshot snapshot() {
        return new Snapshot(
                properties.isEnabled(),
                properties.getMaxConcurrent(),
                inUse.get(),
                maxObserved.get(),
                acquired.sum(),
                rejected.sum(),
                released.sum(),
                acquired.sum() - released.sum());
    }

    public Map<String, StageSnapshot> stageSnapshot() {
        Map<String, StageSnapshot> result = new java.util.LinkedHashMap<>();
        stageCounters.forEach((stage, counters) -> result.put(stage.name(), counters.snapshot()));
        return result;
    }

    private static final class StageCounters {
        private final LongAdder acquired = new LongAdder();
        private final LongAdder rejected = new LongAdder();
        private final LongAdder released = new LongAdder();
        private StageSnapshot snapshot() {
            return new StageSnapshot(acquired.sum(), rejected.sum(), released.sum());
        }
    }

    @Getter
    public static class StageSnapshot {
        private final long acquired;
        private final long rejected;
        private final long released;
        StageSnapshot(long acquired, long rejected, long released) {
            this.acquired = acquired;
            this.rejected = rejected;
            this.released = released;
        }
    }

    @Getter
    public static class Snapshot {
        private final boolean enabled;
        private final int configuredLimit;
        private final int currentInUse;
        private final int maxObservedInUse;
        private final long acquired;
        private final long rejected;
        private final long released;
        private final long permitLeak;

        public Snapshot(boolean enabled, int configuredLimit, int currentInUse,
                int maxObservedInUse, long acquired, long rejected, long released,
                long permitLeak) {
            this.enabled = enabled;
            this.configuredLimit = configuredLimit;
            this.currentInUse = currentInUse;
            this.maxObservedInUse = maxObservedInUse;
            this.acquired = acquired;
            this.rejected = rejected;
            this.released = released;
            this.permitLeak = permitLeak;
        }
    }
}
