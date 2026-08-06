package com.example.doenggameflux.dispatcher;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.time.Duration;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.ToDoubleFunction;
import org.springframework.stereotype.Component;

@Component
public class DispatcherMetrics {

    private final MeterRegistry registry;

    public DispatcherMetrics(MeterRegistry registry) {
        this.registry = Objects.requireNonNull(registry, "registry");
    }

    void bind(String dispatcher, Object queueOwner, ToDoubleFunction<Object> queueDepth,
              AtomicInteger active) {
        Gauge.builder("doeng.dispatcher.queue.depth", queueOwner, queueDepth)
                .tag("dispatcher", dispatcher)
                .description("Current bounded dispatcher queue depth")
                .register(registry);
        Gauge.builder("doeng.dispatcher.active", active, AtomicInteger::doubleValue)
                .tag("dispatcher", dispatcher)
                .description("Current downstream invocations owned by the dispatcher")
                .register(registry);
    }

    void enqueued(String dispatcher) {
        counter(dispatcher, "enqueued", "none").increment();
    }

    void dequeued(String dispatcher, Duration queueWait) {
        counter(dispatcher, "dequeued", "none").increment();
        Timer.builder("doeng.dispatcher.queue.wait")
                .tag("dispatcher", dispatcher)
                .publishPercentileHistogram()
                .register(registry)
                .record(queueWait);
    }

    void rejected(String dispatcher) {
        counter(dispatcher, "rejected", "queue_full").increment();
    }

    void cancelled(String dispatcher) {
        counter(dispatcher, "cancelled", "none").increment();
    }

    void deadline(String dispatcher, String phase) {
        counter(dispatcher, "deadline", phase).increment();
    }

    void completed(String dispatcher) {
        counter(dispatcher, "completed", "none").increment();
    }

    void failed(String dispatcher, Throwable error) {
        counter(dispatcher, "failed", error.getClass().getSimpleName()).increment();
    }

    void resultEmissionFailure(String dispatcher, Sinks.EmitResult result) {
        counter(dispatcher, "result_emission_failed", result.name()).increment();
    }

    private Counter counter(String dispatcher, String event, String detail) {
        return Counter.builder("doeng.dispatcher.events")
                .tag("dispatcher", dispatcher)
                .tag("event", event)
                .tag("detail", detail)
                .register(registry);
    }
}
