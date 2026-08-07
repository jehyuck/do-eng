package com.example.doenggameflux.dispatcher;

import java.util.Objects;
import java.util.Queue;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.DisposableBean;
import org.springframework.beans.factory.InitializingBean;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;

public abstract class AbstractSinkDispatcher<I, O>
        implements SinkDispatcher<I, O>, InitializingBean, DisposableBean {

    private final Logger log = LoggerFactory.getLogger(getClass());
    private final DispatcherSpec spec;
    private final Queue<DispatchWork<I, O>> queue;
    private final Sinks.Many<DispatchWork<I, O>> workSink;
    private final DispatcherMetrics metrics;
    private final AtomicInteger active = new AtomicInteger();
    private final Object emissionMonitor = new Object();
    private volatile Disposable subscription;
    private volatile boolean stopped;

    protected AbstractSinkDispatcher(DispatcherSpec spec) {
        this(spec, null);
    }

    protected AbstractSinkDispatcher(DispatcherSpec spec, DispatcherMetrics metrics) {
        this.spec = Objects.requireNonNull(spec, "spec");
        this.metrics = metrics;
        this.queue = new ArrayBlockingQueue<>(spec.getQueueCapacity());
        this.workSink = Sinks.many().unicast().onBackpressureBuffer(queue);
        if (metrics != null) {
            metrics.bind(spec.getName(), queue, active);
        }
    }

    @Override
    public final void afterPropertiesSet() {
        if (subscription != null) {
            throw new IllegalStateException(spec.getName() + " dispatcher already started");
        }
        subscription = workSink.asFlux()
                .flatMap(this::process, spec.getConcurrency(), 1)
                .subscribe(
                        ignored -> { },
                        error -> log.error("{} dispatcher consumer terminated", spec.getName(), error));
    }

    @Override
    public final Mono<O> dispatch(MissionExecutionContext context, I input) {
        Objects.requireNonNull(context, "context");
        Objects.requireNonNull(input, "input");
        return Mono.defer(() -> enqueue(context, input));
    }

    protected abstract Mono<O> invoke(MissionExecutionContext context, I input);

    protected final DispatcherSpec getSpec() {
        return spec;
    }

    protected final int queuedWorkCount() {
        return queue.size();
    }

    private Mono<O> enqueue(MissionExecutionContext context, I input) {
        if (context.isExpired()) {
            recordDeadline("BEFORE_ENQUEUE");
            return Mono.error(deadline(context, "BEFORE_ENQUEUE"));
        }

        DispatchWork<I, O> work = DispatchWork.create(context, input);
        Sinks.EmitResult emitResult;
        synchronized (emissionMonitor) {
            if (stopped) {
                return Mono.error(new IllegalStateException(spec.getName() + " dispatcher is stopped"));
            }
            // Sinks.Many.tryEmitNext fails fast with FAIL_NON_SERIALIZED when
            // multiple request threads emit concurrently. Serialize only the
            // emission boundary; downstream work remains reactive and bounded
            // by flatMap concurrency.
            emitResult = workSink.tryEmitNext(work);
        }
        if (emitResult.isFailure()) {
            if (metrics != null) metrics.rejected(spec.getName());
            return Mono.error(new DispatcherQueueRejectedException(
                    spec.getName(), context.getRequestId(), emitResult));
        }
        if (metrics != null) metrics.enqueued(spec.getName());

        return work.awaitResult()
                .timeout(
                        context.remaining(),
                        Mono.defer(() -> {
                            recordDeadline("AWAITING_RESULT");
                            return Mono.error(deadline(context, "AWAITING_RESULT"));
                        }));
    }

    private Mono<Void> process(DispatchWork<I, O> work) {
        if (work.isCancelled()) {
            if (metrics != null) metrics.cancelled(spec.getName());
            return Mono.empty();
        }
        if (work.getContext().isExpired()) {
            recordDeadline("BEFORE_EXECUTION");
            emitError(work, deadline(work.getContext(), "BEFORE_EXECUTION"));
            return Mono.empty();
        }

        if (metrics != null) metrics.dequeued(spec.getName(), work.queueWait());
        active.incrementAndGet();

        return Mono.defer(() -> invoke(work.getContext(), work.getInput()))
                .timeout(work.getContext().remaining())
                .switchIfEmpty(Mono.error(new IllegalStateException(
                        spec.getName() + " dispatcher returned an empty result")))
                .doOnNext(result -> {
                    Sinks.EmitResult emitResult = work.complete(result);
                    if (metrics == null) return;
                    if (emitResult.isSuccess()) {
                        metrics.completed(spec.getName());
                    } else {
                        metrics.resultEmissionFailure(spec.getName(), emitResult);
                    }
                })
                .onErrorResume(error -> {
                    Throwable normalized = normalize(error, work.getContext());
                    if (normalized instanceof DispatcherDeadlineExceededException) {
                        recordDeadline("DURING_EXECUTION");
                    }
                    emitError(work, normalized);
                    return Mono.empty();
                })
                // Decrement before the terminal signal reaches flatMap so the
                // next slot cannot be observed while the previous work is
                // still counted as active by downstream instrumentation.
                .doOnTerminate(active::decrementAndGet)
                .doOnCancel(active::decrementAndGet)
                .then();
    }

    private void emitError(DispatchWork<I, O> work, Throwable error) {
        Sinks.EmitResult emitResult = work.fail(error);
        if (metrics == null) return;
        if (emitResult.isSuccess()) {
            metrics.failed(spec.getName(), error);
        } else {
            metrics.resultEmissionFailure(spec.getName(), emitResult);
        }
    }

    private Throwable normalize(Throwable error, MissionExecutionContext context) {
        if (error instanceof TimeoutException) {
            return deadline(context, "DURING_EXECUTION");
        }
        return error;
    }

    private void recordDeadline(String phase) {
        if (metrics != null) metrics.deadline(spec.getName(), phase);
    }

    private DispatcherDeadlineExceededException deadline(
            MissionExecutionContext context,
            String phase) {
        return new DispatcherDeadlineExceededException(
                spec.getName(), context.getRequestId(), phase);
    }

    @Override
    public final void destroy() {
        synchronized (emissionMonitor) {
            stopped = true;
            workSink.tryEmitComplete();
        }
        Disposable current = subscription;
        if (current != null) {
            current.dispose();
        }
    }
}
