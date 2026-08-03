package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.netty.channel.Channel;
import io.netty.util.AttributeKey;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import reactor.netty.Connection;
import reactor.netty.ConnectionObserver;
import reactor.netty.DisposableServer;
import reactor.netty.http.client.HttpClient;
import reactor.netty.http.server.HttpServer;
import reactor.netty.resources.ConnectionProvider;

class FreshFirstLifecyclePolicyTest {

    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(5);
    private static final Duration EVICTION_WAIT_BOUND = Duration.ofSeconds(6);
    private static final AttributeKey<String> REQUEST_ID =
            AttributeKey.valueOf("exp118.request-id");

    @Test
    void gateA_baselineDefaultsReuseAnIdleConnection() throws Exception {
        DisposableServer server = fastServer();
        ConnectionProvider provider = provider(ExternalLeasingStrategy.FIFO, 0, 0, 2);
        try {
            ChannelTrace trace = new ChannelTrace();
            HttpClient client = observedClient(provider, trace);

            assertEquals("ok", get(client, server, "/fast", "A"));
            assertTrue(trace.releaseObserved("A").await(
                    REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS));
            assertEquals("ok", get(client, server, "/fast", "B"));

            assertEquals(trace.channelFor("A"), trace.channelFor("B"));
            System.out.printf("EXP118_GATE_A channelA=%s channelB=%s%n",
                    trace.channelFor("A"), trace.channelFor("B"));
        } finally {
            dispose(provider, server);
        }
    }

    @Test
    void gateB_lifoUsesTheMostRecentlyReleasedIdleChannel() throws Exception {
        HoldGates gates = new HoldGates();
        DisposableServer server = heldResponseServer(gates);
        ConnectionProvider provider = provider(ExternalLeasingStrategy.LIFO, 0, 0, 2);
        try {
            ChannelTrace trace = new ChannelTrace();
            HttpClient client = observedClient(provider, trace);

            CompletableFuture<String> a = getAsync(client, server, "/hold/A", "A");
            CompletableFuture<String> b = getAsync(client, server, "/hold/B", "B");
            assertTrue(gates.handlersArrived.await(REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS),
                    "A and B handlers must arrive before either response is released");

            assertNotEquals(trace.channelFor("A"), trace.channelFor("B"),
                    "A and B must occupy distinct channels");
            gates.release("A");
            assertEquals("A", a.get(REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS));
            assertTrue(trace.releaseObserved("A").await(REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS),
                    "A pool release must be observed before B is released");

            gates.release("B");
            assertEquals("B", b.get(REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS));
            assertTrue(trace.releaseObserved("B").await(REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS),
                    "B pool release must be observed before C acquires a channel");

            assertEquals("C", get(client, server, "/fast", "C"));
            assertEquals(trace.channelFor("B"), trace.channelFor("C"),
                    "LIFO must lease the most recently released B channel to C");
            System.out.printf("EXP118_GATE_B channelA=%s channelB=%s channelC=%s%n",
                    trace.channelFor("A"), trace.channelFor("B"), trace.channelFor("C"));
        } finally {
            dispose(provider, server);
        }
    }

    @Test
    void gateC_backgroundEvictionClosesAnIdleChannelWithoutAnotherAcquire() throws Exception {
        DisposableServer server = longIdleServer();
        ConnectionProvider provider = provider(ExternalLeasingStrategy.LIFO, 3000, 1000, 2);
        try {
            ChannelTrace trace = new ChannelTrace();
            HttpClient client = observedClient(provider, trace);

            assertEquals("ok", get(client, server, "/fast", "EVICT-1"));
            assertTrue(trace.releaseObserved("EVICT-1").await(
                    REQUEST_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS));
            String evictedChannel = trace.channelFor("EVICT-1");
            long releasedAt = trace.releaseTimeNanos("EVICT-1");

            assertTrue(trace.closeObserved(evictedChannel).await(
                    EVICTION_WAIT_BOUND.toMillis(), TimeUnit.MILLISECONDS),
                    "fixed 6s bound = 3s idle eligibility + 1s scan + 2s scheduler margin");
            long elapsedMs = Duration.ofNanos(trace.closeTimeNanos(evictedChannel) - releasedAt).toMillis();
            assertTrue(elapsedMs >= 3000,
                    "background eviction must not close the released channel before maxIdleTime");

            assertEquals("ok", get(client, server, "/fast", "EVICT-2"));
            assertNotEquals(evictedChannel, trace.channelFor("EVICT-2"),
                    "the request after background eviction must use a new channel");
            System.out.printf("EXP118_GATE_C evictedChannel=%s nextChannel=%s elapsedMs=%d%n",
                    evictedChannel, trace.channelFor("EVICT-2"), elapsedMs);
        } finally {
            dispose(provider, server);
        }
    }

    @Test
    void gateD_backgroundEvictionDoesNotInterruptAnActiveResponse() {
        DisposableServer server = HttpServer.create()
                .port(0)
                .idleTimeout(Duration.ofSeconds(20))
                .route(routes -> routes.get("/slow", (request, response) ->
                        response.sendString(Mono.delay(Duration.ofSeconds(2)).map(ignored -> "ok"))))
                .bindNow();
        ConnectionProvider provider = provider(ExternalLeasingStrategy.LIFO, 3000, 1000, 2);
        try {
            ChannelTrace trace = new ChannelTrace();
            HttpClient client = observedClient(provider, trace);
            long startedAt = System.nanoTime();

            assertEquals("ok", get(client, server, "/slow", "SLOW"));
            long elapsedMs = Duration.ofNanos(System.nanoTime() - startedAt).toMillis();

            assertTrue(elapsedMs >= 1800, "the active two-second response must complete normally");
            assertFalse(trace.closedBeforeRelease("SLOW"),
                    "an idle eviction policy must not close an active response channel");
            System.out.printf("EXP118_GATE_D activeResponseMs=%d%n", elapsedMs);
        } finally {
            dispose(provider, server);
        }
    }

    private ConnectionProvider provider(
            ExternalLeasingStrategy strategy,
            long maxIdleTimeMs,
            long evictionIntervalMs,
            int maxConnections) {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setSharedPool(new ExternalServiceProperties.PoolSettings(maxConnections, maxConnections * 2));
        properties.setLeasingStrategy(strategy);
        properties.setMaxIdleTimeMs(maxIdleTimeMs);
        properties.setBackgroundEvictionIntervalMs(evictionIntervalMs);
        return new ExternalHttpClientConfig().sharedConnectionProvider(
                properties, new DiagnosticProperties());
    }

    private HttpClient observedClient(ConnectionProvider provider, ChannelTrace trace) {
        return HttpClient.create(provider)
                .doOnConnected(connection -> {
                    Channel channel = connection.channel();
                    trace.registerChannel(channel);
                })
                .doOnRequest((request, connection) -> {
                    String requestId = request.requestHeaders().get("X-Exp118-Request-Id");
                    connection.channel().attr(REQUEST_ID).set(requestId);
                    trace.requestBound(requestId, connection.channel());
                })
                .observe(new ConnectionObserver() {
                    @Override
                    public void onStateChange(Connection connection, State state) {
                        if (state == State.RELEASED) {
                            String requestId = connection.channel().attr(REQUEST_ID).get();
                            trace.released(requestId, connection.channel());
                        }
                    }
                });
    }

    private CompletableFuture<String> getAsync(
            HttpClient client,
            DisposableServer server,
            String path,
            String requestId) {
        return client.headers(headers -> headers.set("X-Exp118-Request-Id", requestId))
                .get()
                .uri("http://127.0.0.1:" + server.port() + path)
                .responseSingle((response, body) -> body.asString())
                .toFuture();
    }

    private String get(HttpClient client, DisposableServer server, String path, String requestId) {
        return getAsync(client, server, path, requestId).join();
    }

    private DisposableServer fastServer() {
        return HttpServer.create()
                .port(0)
                .idleTimeout(Duration.ofSeconds(20))
                .route(routes -> routes.get("/fast", (request, response) ->
                        response.sendString(Mono.just("ok"))))
                .bindNow();
    }

    private DisposableServer longIdleServer() {
        return HttpServer.create()
                .port(0)
                .idleTimeout(Duration.ofSeconds(20))
                .route(routes -> routes.get("/fast", (request, response) ->
                        response.sendString(Mono.just("ok"))))
                .bindNow();
    }

    private DisposableServer heldResponseServer(HoldGates gates) {
        return HttpServer.create()
                .port(0)
                .idleTimeout(Duration.ofSeconds(20))
                .route(routes -> routes.get("/hold/{id}", (request, response) -> {
                    String id = request.param("id");
                    gates.arrived(id);
                    return gates.awaitRelease(id)
                            .then(response.sendString(Mono.just(id)).then());
                }).get("/fast", (request, response) -> response.sendString(Mono.just("C"))))
                .bindNow();
    }

    private void dispose(ConnectionProvider provider, DisposableServer server) {
        provider.disposeLater().block(REQUEST_TIMEOUT);
        server.disposeNow();
    }

    private static final class HoldGates {
        private final CountDownLatch handlersArrived = new CountDownLatch(2);
        private final Map<String, Sinks.One<Void>> releases = new ConcurrentHashMap<>();

        private void arrived(String id) {
            releases.computeIfAbsent(id, ignored -> Sinks.one());
            handlersArrived.countDown();
        }

        private Mono<Void> awaitRelease(String id) {
            return releases.computeIfAbsent(id, ignored -> Sinks.one()).asMono();
        }

        private void release(String id) {
            assertEquals(Sinks.EmitResult.OK,
                    releases.get(id).tryEmitEmpty(), "response release signal must be emitted once");
        }
    }

    private static final class ChannelTrace {
        private final Map<String, String> channelsByRequest = new ConcurrentHashMap<>();
        private final Map<String, CountDownLatch> releasesByRequest = new ConcurrentHashMap<>();
        private final Map<String, Long> releaseTimes = new ConcurrentHashMap<>();
        private final Map<String, CountDownLatch> closesByChannel = new ConcurrentHashMap<>();
        private final Map<String, Long> closeTimes = new ConcurrentHashMap<>();
        private final AtomicReference<String> activeRequest = new AtomicReference<>();
        private final AtomicLong activeCloseBeforeRelease = new AtomicLong();

        private void registerChannel(Channel channel) {
            String channelId = channel.id().asLongText();
            closesByChannel.computeIfAbsent(channelId, ignored -> new CountDownLatch(1));
            channel.closeFuture().addListener(ignored -> {
                closeTimes.put(channelId, System.nanoTime());
                String requestId = channel.attr(REQUEST_ID).get();
                if (requestId != null && releaseTimes.get(requestId) == null) {
                    activeCloseBeforeRelease.incrementAndGet();
                }
                closesByChannel.get(channelId).countDown();
            });
        }

        private void requestBound(String requestId, Channel channel) {
            activeRequest.set(requestId);
            channelsByRequest.put(requestId, channel.id().asLongText());
        }

        private void released(String requestId, Channel channel) {
            if (requestId != null) {
                releaseTimes.put(requestId, System.nanoTime());
                releasesByRequest.computeIfAbsent(requestId, ignored -> new CountDownLatch(1)).countDown();
            }
        }

        private String channelFor(String requestId) {
            return channelsByRequest.get(requestId);
        }

        private CountDownLatch releaseObserved(String requestId) {
            return releasesByRequest.computeIfAbsent(requestId, ignored -> new CountDownLatch(1));
        }

        private long releaseTimeNanos(String requestId) {
            return releaseTimes.get(requestId);
        }

        private CountDownLatch closeObserved(String channelId) {
            return closesByChannel.get(channelId);
        }

        private long closeTimeNanos(String channelId) {
            return closeTimes.get(channelId);
        }

        private boolean closedBeforeRelease(String requestId) {
            return activeCloseBeforeRelease.get() > 0 && requestId.equals(activeRequest.get());
        }
    }
}
