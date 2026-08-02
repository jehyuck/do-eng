package com.example.doenggameflux.component;

import com.example.doenggameflux.config.AdmissionMode;
import com.example.doenggameflux.config.AdmissionProperties;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.EnumMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.Supplier;
import lombok.Getter;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;
import reactor.core.publisher.SignalType;

/**
 * Lazy whole-request admission/observation boundary.
 *
 * The supplier is not evaluated until subscription. In ENFORCE mode a rejected
 * request returns before the body or any downstream WebClient/R2DBC publisher
 * can be subscribed. Every acquired observation is released from doFinally.
 */
@Component
public class AiOutboundAdmissionGate {

    private final AdmissionProperties properties;
    private final AtomicInteger inFlight = new AtomicInteger();
    private final AtomicInteger maxObserved = new AtomicInteger();
    private final LongAdder started = new LongAdder();
    private final LongAdder completed = new LongAdder();
    private final LongAdder rejected = new LongAdder();
    private final LongAdder released = new LongAdder();
    private final LongAdder cancelled = new LongAdder();
    private final LongAdder wouldReject = new LongAdder();
    private final Counter startedCounter;
    private final Counter completedCounter;
    private final Counter rejectedCounter;
    private final Counter releasedCounter;
    private final Counter cancelledCounter;
    private final Counter wouldRejectCounter;
    private final Map<OutboundStage, StageCounters> stageCounters = new EnumMap<>(OutboundStage.class);

    public AiOutboundAdmissionGate(AdmissionProperties properties, MeterRegistry registry) {
        this.properties = properties;
        Gauge.builder("doeng.admission.mode", properties, p -> p.resolvedMode().ordinal())
                .register(registry);
        Gauge.builder("doeng.admission.configured_limit", properties, p -> p.getMaxConcurrent())
                .register(registry);
        Gauge.builder("doeng.admission.in_flight", inFlight, AtomicInteger::get)
                .register(registry);
        Gauge.builder("doeng.admission.max_observed", maxObserved, AtomicInteger::get)
                .register(registry);
        this.startedCounter = Counter.builder("doeng.admission.started").register(registry);
        this.completedCounter = Counter.builder("doeng.admission.completed").register(registry);
        this.rejectedCounter = Counter.builder("doeng.admission.rejected").register(registry);
        this.releasedCounter = Counter.builder("doeng.admission.released").register(registry);
        this.cancelledCounter = Counter.builder("doeng.admission.cancelled").register(registry);
        this.wouldRejectCounter = Counter.builder("doeng.admission.would_reject").register(registry);
        for (OutboundStage stage : OutboundStage.values()) {
            stageCounters.put(stage, new StageCounters());
        }
    }

    public <T> Mono<T> execute(Supplier<Mono<T>> action) {
        return execute(null, action);
    }

    public <T> Mono<T> execute(OutboundStage stage, Supplier<Mono<T>> action) {
        return Mono.defer(() -> {
            AdmissionMode mode = properties.resolvedMode();
            if (mode == AdmissionMode.OFF) {
                return action.get();
            }

            if (mode == AdmissionMode.ENFORCE && !tryAcquireEnforce()) {
                recordRejected(stage);
                return Mono.error(new AiCapacityExceededException());
            }

            boolean overLimit = mode == AdmissionMode.OBSERVE && acquireObserve();
            if (mode == AdmissionMode.ENFORCE) {
                // tryAcquireEnforce has already incremented the counter.
                started.increment();
                startedCounter.increment();
                recordStageStarted(stage, false);
            } else {
                started.increment();
                startedCounter.increment();
                if (overLimit) {
                    wouldReject.increment();
                    wouldRejectCounter.increment();
                }
                recordStageStarted(stage, overLimit);
            }

            final Mono<T> source;
            try {
                source = action.get();
            } catch (Throwable error) {
                release(stage, SignalType.ON_ERROR);
                return Mono.error(error);
            }
            return source.doFinally(signal -> release(stage, signal));
        });
    }

    public <T> Mono<T> executeStage(OutboundStage stage, Supplier<Mono<T>> action) {
        return properties.isPerOutboundCall() ? execute(stage, action) : Mono.defer(action);
    }

    public boolean isPerOutboundCall() {
        return properties.isPerOutboundCall();
    }

    public AdmissionMode getMode() {
        return properties.resolvedMode();
    }

    private boolean tryAcquireEnforce() {
        while (true) {
            int current = inFlight.get();
            if (current >= properties.getMaxConcurrent()) {
                return false;
            }
            if (inFlight.compareAndSet(current, current + 1)) {
                observeMax(current + 1);
                return true;
            }
        }
    }

    /** In OBSERVE mode the request is always admitted; over-limit is telemetry. */
    private boolean acquireObserve() {
        while (true) {
            int current = inFlight.get();
            if (inFlight.compareAndSet(current, current + 1)) {
                observeMax(current + 1);
                return current >= properties.getMaxConcurrent();
            }
        }
    }

    private void observeMax(int current) {
        maxObserved.accumulateAndGet(current, Math::max);
    }

    private void recordStageStarted(OutboundStage stage, boolean wouldRejectStage) {
        if (stage == null) {
            return;
        }
        StageCounters counters = stageCounters.get(stage);
        counters.started.increment();
        if (wouldRejectStage) {
            counters.wouldReject.increment();
        }
    }

    private void recordRejected(OutboundStage stage) {
        rejected.increment();
        rejectedCounter.increment();
        if (stage != null) {
            stageCounters.get(stage).rejected.increment();
        }
        wouldReject.increment();
        wouldRejectCounter.increment();
    }

    private void release(OutboundStage stage, SignalType signal) {
        int remaining = inFlight.decrementAndGet();
        if (remaining < 0) {
            // This is an implementation invariant violation, not a reason to
            // hide a leak. Keep the observable value non-negative for operators.
            inFlight.compareAndSet(remaining, 0);
        }
        released.increment();
        releasedCounter.increment();
        if (signal == SignalType.CANCEL) {
            cancelled.increment();
            cancelledCounter.increment();
        } else {
            completed.increment();
            completedCounter.increment();
        }
        if (stage != null) {
            StageCounters counters = stageCounters.get(stage);
            counters.released.increment();
            if (signal == SignalType.CANCEL) {
                counters.cancelled.increment();
            } else {
                counters.completed.increment();
            }
        }
    }

    public Snapshot snapshot() {
        return new Snapshot(
                properties.resolvedMode(),
                properties.isEnabled(),
                properties.getMaxConcurrent(),
                inFlight.get(),
                maxObserved.get(),
                started.sum(),
                completed.sum(),
                rejected.sum(),
                released.sum(),
                cancelled.sum(),
                started.sum() - released.sum(),
                wouldReject.sum());
    }

    public Map<String, StageSnapshot> stageSnapshot() {
        Map<String, StageSnapshot> result = new java.util.LinkedHashMap<>();
        stageCounters.forEach((stage, counters) -> result.put(stage.name(), counters.snapshot()));
        return result;
    }

    private static final class StageCounters {
        private final LongAdder started = new LongAdder();
        private final LongAdder completed = new LongAdder();
        private final LongAdder rejected = new LongAdder();
        private final LongAdder released = new LongAdder();
        private final LongAdder cancelled = new LongAdder();
        private final LongAdder wouldReject = new LongAdder();

        private StageSnapshot snapshot() {
            return new StageSnapshot(started.sum(), completed.sum(), rejected.sum(),
                    released.sum(), cancelled.sum(), wouldReject.sum());
        }
    }

    @Getter
    public static class StageSnapshot {
        private final long started;
        private final long completed;
        private final long rejected;
        private final long released;
        private final long cancelled;
        private final long wouldReject;

        StageSnapshot(long started, long completed, long rejected, long released,
                long cancelled, long wouldReject) {
            this.started = started;
            this.completed = completed;
            this.rejected = rejected;
            this.released = released;
            this.cancelled = cancelled;
            this.wouldReject = wouldReject;
        }
    }

    @Getter
    public static class Snapshot {
        private final AdmissionMode mode;
        private final boolean enabled;
        private final int configuredLimit;
        private final int currentInUse;
        private final int maxObservedInUse;
        private final long started;
        private final long completed;
        private final long rejected;
        private final long released;
        private final long cancelled;
        private final long permitLeak;
        private final long wouldReject;

        public Snapshot(AdmissionMode mode, boolean enabled, int configuredLimit,
                int currentInUse, int maxObservedInUse, long started, long completed,
                long rejected, long released, long cancelled, long permitLeak,
                long wouldReject) {
            this.mode = mode;
            this.enabled = enabled;
            this.configuredLimit = configuredLimit;
            this.currentInUse = currentInUse;
            this.maxObservedInUse = maxObservedInUse;
            this.started = started;
            this.completed = completed;
            this.rejected = rejected;
            this.released = released;
            this.cancelled = cancelled;
            this.permitLeak = permitLeak;
            this.wouldReject = wouldReject;
        }

        /** Compatibility aliases for existing admission artifact readers. */
        public long getAcquired() {
            return started;
        }

        public long getMaxObserved() {
            return maxObservedInUse;
        }
    }
}
