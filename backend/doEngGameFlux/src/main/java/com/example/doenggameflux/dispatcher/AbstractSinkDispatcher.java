package com.example.doenggameflux.dispatcher;

import java.util.Objects;
import java.util.Queue;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeoutException;
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
    private volatile Disposable subscription;

    protected AbstractSinkDispatcher(DispatcherSpec spec) {
        this.spec = Objects.requireNonNull(spec, "spec");
        this.queue = new ArrayBlockingQueue<>(spec.getQueueCapacity());
        this.workSink = Sinks.many().unicast().onBackpressureBuffer(queue);
    }

    @Override
    public final void afterPropertiesSet() {
        if (subscription != null) {
            throw new IllegalStateException(spec.getName() + " dispatcher already started");
        }
        subscription = workSink.asFlux()
                .flatMap(this::process, spec.getConcurrency())
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
            return Mono.error(deadline(context, "BEFORE_ENQUEUE"));
        }

        DispatchWork<I, O> work = DispatchWork.create(context, input);
        Sinks.EmitResult emitResult = workSink.tryEmitNext(work);
        if (emitResult.isFailure()) {
            return Mono.error(new DispatcherQueueRejectedException(
                    spec.getName(), context.getRequestId(), emitResult));
        }

        return work.awaitResult()
                .timeout(
                        context.remaining(),
                        Mono.error(deadline(context, "AWAITING_RESULT")));
    }

    private Mono<Void> process(DispatchWork<I, O> work) {
        if (work.isCancelled()) {
            return Mono.empty();
        }
        if (work.getContext().isExpired()) {
            work.fail(deadline(work.getContext(), "BEFORE_EXECUTION"));
            return Mono.empty();
        }

        return Mono.defer(() -> invoke(work.getContext(), work.getInput()))
                .timeout(work.getContext().remaining())
                .switchIfEmpty(Mono.error(new IllegalStateException(
                        spec.getName() + " dispatcher returned an empty result")))
                .doOnNext(work::complete)
                .onErrorResume(error -> {
                    work.fail(normalize(error, work.getContext()));
                    return Mono.empty();
                })
                .then();
    }

    private Throwable normalize(Throwable error, MissionExecutionContext context) {
        if (error instanceof TimeoutException) {
            return deadline(context, "DURING_EXECUTION");
        }
        return error;
    }

    private DispatcherDeadlineExceededException deadline(
            MissionExecutionContext context,
            String phase) {
        return new DispatcherDeadlineExceededException(
                spec.getName(), context.getRequestId(), phase);
    }

    @Override
    public final void destroy() {
        workSink.tryEmitComplete();
        Disposable current = subscription;
        if (current != null) {
            current.dispose();
        }
    }
}
