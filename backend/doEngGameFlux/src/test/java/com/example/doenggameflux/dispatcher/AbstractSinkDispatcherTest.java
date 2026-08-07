package com.example.doenggameflux.dispatcher;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import reactor.test.StepVerifier;

class AbstractSinkDispatcherTest {

    private final List<TestDispatcher> dispatchers = new ArrayList<>();

    @AfterEach
    void tearDown() {
        dispatchers.forEach(TestDispatcher::destroy);
    }

    @Test
    void limitsConcurrentExecutionToConfiguredConcurrency() {
        TestDispatcher dispatcher = dispatcher(2, 8);
        Map<Integer, Sinks.One<Integer>> releases = new HashMap<>();
        for (int i = 0; i < 5; i++) {
            releases.put(i, Sinks.one());
        }
        dispatcher.invoker = value -> releases.get(value).asMono();

        List<Integer> values = new CopyOnWriteArrayList<>();
        List<Disposable> subscriptions = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            subscriptions.add(dispatcher.dispatch(context("request-" + i), i)
                    .subscribe(values::add));
        }

        await(() -> dispatcher.started.get() == 2);
        assertEquals(2, dispatcher.maxActive.get());

        for (int i = 0; i < 5; i++) {
            releases.get(i).tryEmitValue(i);
            int expectedStarted = Math.min(i + 3, 5);
            await(() -> dispatcher.started.get() >= expectedStarted || values.size() == 5);
        }

        await(() -> values.size() == 5);
        assertEquals(2, dispatcher.maxActive.get());
        subscriptions.forEach(Disposable::dispose);
    }

    @Test
    void serializesConcurrentProducerEmissions() throws Exception {
        int producerCount = 32;
        TestDispatcher dispatcher = dispatcher(producerCount, producerCount * 2);
        ExecutorService executor = Executors.newFixedThreadPool(producerCount);
        CountDownLatch ready = new CountDownLatch(producerCount);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<Integer>> futures = new ArrayList<>();

        try {
            for (int i = 0; i < producerCount; i++) {
                final int value = i;
                futures.add(executor.submit(() -> {
                    ready.countDown();
                    if (!start.await(2, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("concurrent producer start timed out");
                    }
                    return dispatcher.dispatch(context("concurrent-" + value), value).block();
                }));
            }

            assertTrue(ready.await(2, TimeUnit.SECONDS));
            start.countDown();

            for (int i = 0; i < producerCount; i++) {
                assertEquals(i, futures.get(i).get(2, TimeUnit.SECONDS));
            }
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void rejectsWhenBoundedQueueIsFull() {
        TestDispatcher dispatcher = dispatcher(1, 1);
        dispatcher.invoker = ignored -> Mono.never();

        Disposable first = dispatcher.dispatch(context("first"), 1).subscribe();
        await(() -> dispatcher.started.get() == 1);
        Disposable second = dispatcher.dispatch(context("second"), 2).subscribe(
                ignored -> { },
                ignored -> { });

        StepVerifier.create(dispatcher.dispatch(context("third"), 3))
                .expectError(DispatcherQueueRejectedException.class)
                .verify();

        first.dispose();
        second.dispose();
    }

    @Test
    void expiredContextNeverInvokesDownstream() {
        TestDispatcher dispatcher = dispatcher(1, 1);

        StepVerifier.create(dispatcher.dispatch(
                        MissionExecutionContext.start("expired", Duration.ofNanos(1)),
                        1)
                .delaySubscription(Duration.ofMillis(5)))
                .expectErrorMatches(error -> error instanceof DispatcherDeadlineExceededException
                        && error.getMessage().contains("BEFORE_ENQUEUE"))
                .verify();

        assertEquals(0, dispatcher.started.get());
    }

    @Test
    void executionUsesRemainingGlobalDeadline() {
        TestDispatcher dispatcher = dispatcher(1, 1);
        dispatcher.invoker = ignored -> Mono.never();

        StepVerifier.create(dispatcher.dispatch(
                        MissionExecutionContext.start("timeout", Duration.ofMillis(30)),
                        1))
                .expectErrorMatches(error -> error instanceof DispatcherDeadlineExceededException)
                .verify(Duration.ofSeconds(1));
    }

    @Test
    void cancelledQueuedWorkIsSkippedBeforeInvocation() {
        TestDispatcher dispatcher = dispatcher(1, 4);
        Sinks.One<Integer> releaseFirst = Sinks.one();
        dispatcher.invoker = value -> value == 1 ? releaseFirst.asMono() : Mono.just(value);

        Disposable first = dispatcher.dispatch(context("first"), 1).subscribe();
        await(() -> dispatcher.started.get() == 1);

        Disposable cancelled = dispatcher.dispatch(context("cancelled"), 2).subscribe();
        cancelled.dispose();
        releaseFirst.tryEmitValue(1);

        await(() -> dispatcher.active.get() == 0);
        assertEquals(1, dispatcher.started.get());
        first.dispose();
    }

    @Test
    void oneWorkFailureDoesNotTerminateSharedConsumer() {
        TestDispatcher dispatcher = dispatcher(1, 2);
        dispatcher.invoker = value -> value == 1
                ? Mono.error(new IllegalStateException("boom"))
                : Mono.just(value);

        StepVerifier.create(dispatcher.dispatch(context("failed"), 1))
                .expectErrorMessage("boom")
                .verify();

        StepVerifier.create(dispatcher.dispatch(context("next"), 2))
                .expectNext(2)
                .verifyComplete();
    }

    @Test
    void stoppedDispatcherRejectsNewWork() {
        TestDispatcher dispatcher = dispatcher(1, 1);
        dispatcher.destroy();

        StepVerifier.create(dispatcher.dispatch(context("stopped"), 1))
                .expectErrorMatches(error -> error instanceof IllegalStateException
                        && error.getMessage().contains("stopped"))
                .verify();
    }

    private TestDispatcher dispatcher(int concurrency, int queueCapacity) {
        TestDispatcher dispatcher = new TestDispatcher(concurrency, queueCapacity);
        dispatcher.afterPropertiesSet();
        dispatchers.add(dispatcher);
        return dispatcher;
    }

    private MissionExecutionContext context(String requestId) {
        return MissionExecutionContext.start(requestId, Duration.ofSeconds(2));
    }

    private void await(Check check) {
        long deadline = System.nanoTime() + Duration.ofSeconds(2).toNanos();
        while (!check.get() && System.nanoTime() < deadline) {
            Thread.yield();
        }
        assertTrue(check.get(), "condition was not met before timeout");
    }

    private interface Check {
        boolean get();
    }

    private static final class TestDispatcher extends AbstractSinkDispatcher<Integer, Integer> {

        private final AtomicInteger started = new AtomicInteger();
        private final AtomicInteger active = new AtomicInteger();
        private final AtomicInteger maxActive = new AtomicInteger();
        private volatile java.util.function.Function<Integer, Mono<Integer>> invoker = Mono::just;

        private TestDispatcher(int concurrency, int queueCapacity) {
            super(new DispatcherSpec("test", concurrency, queueCapacity));
        }

        @Override
        protected Mono<Integer> invoke(MissionExecutionContext context, Integer input) {
            return Mono.defer(() -> {
                started.incrementAndGet();
                int current = active.incrementAndGet();
                maxActive.accumulateAndGet(current, Math::max);
                return invoker.apply(input)
                        .doOnTerminate(active::decrementAndGet)
                        .doOnCancel(active::decrementAndGet);
            });
        }
    }
}
