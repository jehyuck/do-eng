package com.example.doenggameflux.dispatcher;

import java.time.Duration;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicBoolean;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

final class DispatchWork<I, O> {

    private final MissionExecutionContext context;
    private final I input;
    private final Sinks.One<O> result;
    private final long enqueuedAtNanos;
    private final AtomicBoolean cancelled = new AtomicBoolean(false);

    private DispatchWork(MissionExecutionContext context, I input) {
        this.context = Objects.requireNonNull(context, "context");
        this.input = Objects.requireNonNull(input, "input");
        this.result = Sinks.one();
        this.enqueuedAtNanos = System.nanoTime();
    }

    static <I, O> DispatchWork<I, O> create(MissionExecutionContext context, I input) {
        return new DispatchWork<>(context, input);
    }

    MissionExecutionContext getContext() {
        return context;
    }

    I getInput() {
        return input;
    }

    Duration queueWait() {
        return Duration.ofNanos(Math.max(0L, System.nanoTime() - enqueuedAtNanos));
    }

    boolean isCancelled() {
        return cancelled.get();
    }

    Mono<O> awaitResult() {
        return result.asMono().doOnCancel(() -> cancelled.set(true));
    }

    Sinks.EmitResult complete(O value) {
        return result.tryEmitValue(value);
    }

    Sinks.EmitResult fail(Throwable error) {
        return result.tryEmitError(error);
    }
}
