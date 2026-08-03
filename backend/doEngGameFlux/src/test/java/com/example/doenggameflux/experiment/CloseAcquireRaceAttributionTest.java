package com.example.doenggameflux.experiment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.netty.channel.Channel;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.util.AttributeKey;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.core.publisher.Sinks;
import reactor.netty.ByteBufFlux;
import reactor.netty.Connection;
import reactor.netty.ConnectionObserver;
import reactor.netty.DisposableServer;
import reactor.netty.http.client.HttpClient;
import reactor.netty.http.server.HttpServer;
import reactor.netty.resources.ConnectionProvider;

/** Test-only Experiment 1-16 close/acquire race diagnostic. */
class CloseAcquireRaceAttributionTest {

    private static final int CYCLES = 8;
    private static final Duration WAIT = Duration.ofSeconds(5);
    private static final String STAGE = "AI";
    private static final String ATTRIBUTION = "DETERMINISTIC_SINGLE_FLIGHT_ATTRIBUTION_USED";
    private static final AttributeKey<AtomicLong> LEASE_SEQUENCE =
            AttributeKey.valueOf("exp116.leaseSequence");
    private static final AttributeKey<Boolean> RELEASED = AttributeKey.valueOf("exp116.released");
    private static final AttributeKey<Boolean> CLOSE_LISTENER_REGISTERED =
            AttributeKey.valueOf("exp116.closeListenerRegistered");
    private static final AttributeKey<String> LAST_REQUEST_ID =
            AttributeKey.valueOf("exp116.lastRequestId");
    private static final AttributeKey<String> LAST_ATTEMPT_ID =
            AttributeKey.valueOf("exp116.lastAttemptId");
    private static final AttributeKey<String> SERVER_REQUEST_ID =
            AttributeKey.valueOf("exp116.serverRequestId");
    private static final AttributeKey<String> SERVER_ATTEMPT_ID =
            AttributeKey.valueOf("exp116.serverAttemptId");

    @Test
    void attributesEightCloseAcquireRacesWithoutChangingProductionLifecycle() throws Exception {
        EventRecorder recorder = new EventRecorder();
        Map<String, RaceGate> raceGates = new ConcurrentHashMap<>();
        DisposableServer server = server(recorder, raceGates);
        ConnectionProvider provider = ConnectionProvider.builder("exp116-test-provider")
                .maxConnections(1)
                .pendingAcquireMaxCount(1)
                .pendingAcquireTimeout(Duration.ofSeconds(2))
                .build();
        try {
            HttpClient client = observedClient(provider, recorder);
            List<Map<String, Object>> cycles = new ArrayList<>();

            for (int cycle = 1; cycle <= CYCLES; cycle++) {
                String prefix = "EXP116-C" + cycle;
                RequestResult first = post(client, server, recorder, prefix + "-A", false);
                awaitEvent(recorder, "POOL_RELEASE_OBSERVED", first.requestId, null);

                String bRequestId = prefix + "-B";
                RaceGate gate = new RaceGate();
                raceGates.put(bRequestId, gate);
                RequestResult reused = post(client, server, recorder, bRequestId, true);
                awaitEvent(recorder, "POOL_RELEASE_OBSERVED", reused.requestId, null);

                gate.awaitCloseInitiated();
                String cRequestId = prefix + "-C";
                recorder.record("C_RACE_START_SIGNAL_RECEIVED", cRequestId, cRequestId + "-A1",
                        null, null, "test-barrier");
                RequestResult raced = post(client, server, recorder, cRequestId, false);

                awaitEvent(recorder, "MOCK_CLOSE_FUTURE_COMPLETED", reused.requestId, null);
                awaitEventForChannel(recorder, "CLIENT_CLOSE_FUTURE_COMPLETED", reused.channelId);

                assertTrue(reused.success, "B must establish normal pooled reuse before the race");
                assertEquals(first.channelId, reused.channelId,
                        "A and B must use the same pooled channel before close initiation");
                assertNotEquals(reused.channelId, raced.channelId,
                        "C final channel must differ from the server-closed B channel");

                cycles.add(cycleRow(cycle, first, reused, raced, recorder));
            }

            assertEquals(CYCLES * 3, recorder.mockHandlerCounts().size());
            assertTrue(recorder.mockHandlerCounts().values().stream().allMatch(count -> count == 1),
                    "each logical request must reach the mock exactly once");
            assertEquals(CYCLES, recorder.count("CLIENT_CLOSE_FUTURE_COMPLETED", null,
                    "oldCycleChannel"));

            assertEquals(CYCLES, cycles.size());
            assertTrue(cycles.stream().allMatch(row -> Boolean.TRUE.equals(row.get("raceStartedBeforeMockCloseCompleted"))),
                    "C start signal must not be delayed until mock close completion");
            assertTrue(cycles.stream().allMatch(row -> Boolean.TRUE.equals(row.get("clientCloseFutureObserved"))),
                    "client closeFuture must be observed for every old channel");
            assertTrue(cycles.stream().allMatch(row -> Boolean.TRUE.equals(row.get("nextFinalChannelNew"))),
                    "C final success must use a new channel");

            writeArtifacts(recorder, cycles);
        } finally {
            provider.disposeLater().block(WAIT);
            server.disposeNow();
        }
    }

    private DisposableServer server(EventRecorder recorder, Map<String, RaceGate> raceGates) {
        return HttpServer.create()
                .port(0)
                .doOnConnection(connection -> connection.addHandlerFirst("exp116-server-lifecycle",
                        new ChannelInboundHandlerAdapter() {
                            @Override
                            public void channelInactive(ChannelHandlerContext context) throws Exception {
                                recorder.record("MOCK_CHANNEL_INACTIVE",
                                        context.channel().attr(SERVER_REQUEST_ID).get(),
                                        context.channel().attr(SERVER_ATTEMPT_ID).get(), null,
                                        context.channel(), "mock-channel-handler");
                                super.channelInactive(context);
                            }
                        }))
                .route(routes -> routes.post("/face", (request, response) -> {
                    String requestId = request.requestHeaders().get("X-Exp16-Request-Id");
                    String attemptId = request.requestHeaders().get("X-Exp16-Attempt-Id");
                    boolean raceClose = request.uri().contains("raceClose=true");
                    Connection[] connection = new Connection[1];
                    response.withConnection(value -> connection[0] = value);
                    recorder.incrementMockHandler(requestId);
                    Channel channel = connection[0] == null ? null : connection[0].channel();
                    if (channel != null) {
                        channel.attr(SERVER_REQUEST_ID).set(requestId);
                        channel.attr(SERVER_ATTEMPT_ID).set(attemptId);
                    }
                    recorder.record("MOCK_REQUEST_RECEIVED", requestId, attemptId, null, channel,
                            "mock-server");
                    return request.receive().aggregate().asString()
                            .doOnSuccess(body -> recorder.record("MOCK_REQUEST_BODY_COMPLETED",
                                    requestId, attemptId, null, connection[0].channel(), "mock-server"))
                            .then(Mono.defer(() -> {
                                response.header("X-Exp16-Request-Id", requestId);
                                response.header("X-Exp16-Attempt-Id", attemptId);
                                return response.sendString(Mono.just("{\"result\":true}"))
                                        .then()
                                        .doOnSuccess(ignored -> {
                                            recorder.record("MOCK_RESPONSE_FINISHED", requestId, attemptId,
                                                    null, connection[0].channel(), "mock-server");
                                            if (raceClose) {
                                                connection[0].channel().eventLoop().schedule(() -> {
                                                    Channel raceChannel = connection[0].channel();
                                                    recorder.record("MOCK_CLOSE_INITIATED", requestId,
                                                            attemptId, null, raceChannel, "mock-server");
                                                    RaceGate gate = raceGates.get(requestId);
                                                    if (gate == null) {
                                                        throw new IllegalStateException("missing race gate: " + requestId);
                                                    }
                                                    gate.openAtCloseInitiation();
                                                    raceChannel.close().addListener(closeFuture -> recorder.record(
                                                            "MOCK_CLOSE_FUTURE_COMPLETED", requestId, attemptId,
                                                            null, raceChannel, "mock-server"));
                                                }, 100, TimeUnit.MILLISECONDS);
                                            }
                                        });
                            }));
                }))
                .bindNow();
    }

    private HttpClient observedClient(ConnectionProvider provider, EventRecorder recorder) {
        return HttpClient.create(provider)
                .doOnChannelInit((observer, channel, remoteAddress) -> {
                    if (Boolean.TRUE.equals(channel.attr(CLOSE_LISTENER_REGISTERED).get())) return;
                    channel.attr(CLOSE_LISTENER_REGISTERED).set(true);
                    recorder.record("CLIENT_CLOSE_LISTENER_REGISTERED", null, null, null, channel,
                            "HttpClient.doOnChannelInit");
                    channel.closeFuture().addListener(closeFuture -> recorder.record(
                            "CLIENT_CLOSE_FUTURE_COMPLETED", recorder.requestIdFor(channel),
                            recorder.attemptIdFor(channel), lease(channel), channel,
                            "channel.closeFuture"));
                    channel.pipeline().addFirst("exp116-client-lifecycle", new ChannelInboundHandlerAdapter() {
                        @Override
                        public void channelInactive(ChannelHandlerContext context) throws Exception {
                            recorder.record("CLIENT_CHANNEL_INACTIVE", recorder.requestIdFor(context.channel()),
                                    recorder.attemptIdFor(context.channel()), lease(context.channel()),
                                    context.channel(), "client-channel-handler");
                            super.channelInactive(context);
                        }

                        @Override
                        public void channelUnregistered(ChannelHandlerContext context) throws Exception {
                            recorder.record("CLIENT_CHANNEL_UNREGISTERED", recorder.requestIdFor(context.channel()),
                                    recorder.attemptIdFor(context.channel()), lease(context.channel()),
                                    context.channel(), "client-channel-handler");
                            super.channelUnregistered(context);
                        }
                    });
                })
                .doOnRequest((request, connection) -> {
                    String requestId = request.requestHeaders().get("X-Exp16-Request-Id");
                    String attemptId = request.requestHeaders().get("X-Exp16-Attempt-Id");
                    connection.channel().attr(LAST_REQUEST_ID).set(requestId);
                    connection.channel().attr(LAST_ATTEMPT_ID).set(attemptId);
                    recorder.record("REQUEST_BOUND_TO_CHANNEL", requestId, attemptId,
                            lease(connection.channel()), connection.channel(), "HttpClient.doOnRequest");
                    recorder.record("REQUEST_SENT", requestId, attemptId, lease(connection.channel()),
                            connection.channel(), "HttpClient.doOnRequest");
                })
                .doAfterRequest((request, connection) -> recorder.record("REQUEST_BODY_SENT",
                        request.requestHeaders().get("X-Exp16-Request-Id"),
                        request.requestHeaders().get("X-Exp16-Attempt-Id"), lease(connection.channel()),
                        connection.channel(), "HttpClient.doAfterRequest"))
                .doOnResponse((response, connection) -> recorder.record("CLIENT_RESPONSE_RECEIVED",
                        response.responseHeaders().get("X-Exp16-Request-Id"),
                        response.responseHeaders().get("X-Exp16-Attempt-Id"), lease(connection.channel()),
                        connection.channel(), "HttpClient.doOnResponse"))
                .doAfterResponseSuccess((response, connection) -> recorder.record(
                        "CLIENT_RESPONSE_BODY_COMPLETED",
                        response.responseHeaders().get("X-Exp16-Request-Id"),
                        response.responseHeaders().get("X-Exp16-Attempt-Id"), lease(connection.channel()),
                        connection.channel(), "HttpClient.doAfterResponseSuccess"))
                .observe(new ConnectionObserver() {
                    @Override
                    public void onStateChange(Connection connection, State state) {
                        Channel channel = connection.channel();
                        long sequence = updateLease(channel, state);
                        String requestId = recorder.requestIdFor(channel);
                        String attemptId = recorder.attemptIdFor(channel);
                        if (state == State.CONFIGURED || state == State.ACQUIRED) {
                            recorder.record("POOL_CONNECTION_ACQUIRED", requestId, attemptId, sequence,
                                    channel, "ConnectionObserver." + state);
                        } else if (state == State.RELEASED) {
                            recorder.record("POOL_RELEASE_OBSERVED", requestId, attemptId, sequence,
                                    channel, "ConnectionObserver.RELEASED");
                        } else if ("[request_prepared]".equals(String.valueOf(state))) {
                            recorder.record("REQUEST_PREPARED", requestId, attemptId, sequence,
                                    channel, "ConnectionObserver.REQUEST_PREPARED");
                        }
                    }

                    @Override
                    public void onUncaughtException(Connection connection, Throwable error) {
                        recorder.record("REQUEST_FAILED", recorder.requestIdFor(connection.channel()),
                                recorder.attemptIdFor(connection.channel()), lease(connection.channel()),
                                connection.channel(), "ConnectionObserver." + error.getClass().getSimpleName());
                    }
                });
    }

    private RequestResult post(HttpClient client, DisposableServer server, EventRecorder recorder,
            String requestId, boolean raceClose) {
        String attemptId = requestId + "-A1";
        recorder.beginSingleFlightRequest(requestId, attemptId);
        recorder.record("LOGICAL_REQUEST_CREATED", requestId, attemptId, null, null, ATTRIBUTION);
        try {
            String body = client.headers(headers -> {
                        headers.set("X-Exp16-Request-Id", requestId);
                        headers.set("X-Exp16-Attempt-Id", attemptId);
                    })
                    .post()
                    .uri("http://127.0.0.1:" + server.port() + "/face?raceClose=" + raceClose)
                    .send(ByteBufFlux.fromString(Mono.just("{\"image\":\"fixture\"}")))
                    .responseSingle((response, content) -> content.asString())
                    .block(WAIT);
            recorder.record("REQUEST_SUCCEEDED", requestId, attemptId, null, null,
                    "client-responseSingle");
            return new RequestResult(requestId, attemptId, recorder.lastChannel("REQUEST_SENT", requestId),
                    true, body, null);
        } catch (RuntimeException error) {
            recorder.record("REQUEST_FAILED", requestId, attemptId, null, null,
                    "client-block." + error.getClass().getSimpleName());
            return new RequestResult(requestId, attemptId, recorder.lastChannel("REQUEST_SENT", requestId),
                    false, null, error.getClass().getSimpleName());
        }
    }

    private Map<String, Object> cycleRow(int cycle, RequestResult first, RequestResult reused,
            RequestResult raced, EventRecorder recorder) {
        String cRequestId = raced.requestId;
        String oldChannel = reused.channelId;
        List<Map<String, Object>> cAcquires = recorder.events("POOL_CONNECTION_ACQUIRED", cRequestId);
        boolean oldChannelAcquired = cAcquires.stream().anyMatch(row -> oldChannel.equals(row.get("channelId")));
        boolean oldChannelSent = recorder.events("REQUEST_SENT", cRequestId).stream()
                .anyMatch(row -> oldChannel.equals(row.get("channelId")));
        boolean newChannelAcquired = cAcquires.stream().anyMatch(row -> {
            Object channelId = row.get("channelId");
            return channelId != null && !oldChannel.equals(channelId);
        });
        boolean clientCloseBeforeAcquire = recorder.before("CLIENT_CLOSE_FUTURE_COMPLETED", oldChannel,
                "POOL_CONNECTION_ACQUIRED", cRequestId, true);
        boolean raceStartedBeforeMockCloseCompleted = recorder.before("C_RACE_START_SIGNAL_RECEIVED", cRequestId,
                "MOCK_CLOSE_FUTURE_COMPLETED", reused.requestId);
        boolean clientCloseFutureObserved = recorder.hasEventForChannel("CLIENT_CLOSE_FUTURE_COMPLETED", oldChannel);
        int cMockHandlers = recorder.mockHandlerCounts().getOrDefault(cRequestId, 0);
        String classification = classify(oldChannelAcquired, oldChannelSent, newChannelAcquired,
                clientCloseBeforeAcquire, raced.success, cMockHandlers, recorder.events("REQUEST_FAILED", cRequestId));
        String retry = "OLD_CHANNEL_ACQUIRED_THEN_RETRIED".equals(classification)
                ? "STRONGLY_INFERRED" : "NOT_OBSERVED";

        Map<String, Object> row = new LinkedHashMap<>();
        row.put("cycleId", cycle);
        row.put("aChannelId", first.channelId);
        row.put("bRequestId", reused.requestId);
        row.put("bChannelId", oldChannel);
        row.put("cRequestId", cRequestId);
        row.put("cFinalChannelId", raced.channelId);
        row.put("aToBNormalReuse", first.channelId != null && first.channelId.equals(oldChannel));
        row.put("raceStartedBeforeMockCloseCompleted", raceStartedBeforeMockCloseCompleted);
        row.put("clientCloseFutureObserved", clientCloseFutureObserved);
        row.put("oldChannelAcquiredByC", oldChannelAcquired);
        row.put("oldChannelSentByC", oldChannelSent);
        row.put("newChannelAcquiredByC", newChannelAcquired);
        row.put("nextFinalChannelNew", raced.channelId != null && !oldChannel.equals(raced.channelId));
        row.put("cSuccess", raced.success);
        row.put("cError", raced.errorClass);
        row.put("cMockHandlerCount", cMockHandlers);
        row.put("classification", classification);
        row.put("internalRetryAttribution", retry);
        row.put("mockCloseInitiated", recorder.eventTime("MOCK_CLOSE_INITIATED", reused.requestId));
        row.put("mockCloseFutureCompleted", recorder.eventTime("MOCK_CLOSE_FUTURE_COMPLETED", reused.requestId));
        row.put("clientCloseFutureCompleted", recorder.eventTimeForChannel("CLIENT_CLOSE_FUTURE_COMPLETED", oldChannel));
        row.put("cAcquire", recorder.eventTime("POOL_CONNECTION_ACQUIRED", cRequestId));
        row.put("cRequestSent", recorder.eventTime("REQUEST_SENT", cRequestId));
        return row;
    }

    private String classify(boolean oldAcquired, boolean oldSent, boolean newAcquired,
            boolean clientClosedBeforeAcquire, boolean success, int mockHandlers,
            List<Map<String, Object>> failures) {
        if (!oldAcquired && clientClosedBeforeAcquire && newAcquired && success && mockHandlers == 1) {
            return "POOL_FILTERED_CLOSED_CHANNEL";
        }
        if (oldAcquired && !oldSent && newAcquired && success && mockHandlers == 1
                && !failures.isEmpty()) {
            return "OLD_CHANNEL_ACQUIRED_THEN_RETRIED";
        }
        if (oldAcquired && !oldSent && !success && !newAcquired && !failures.isEmpty()) {
            return "OLD_CHANNEL_ACQUIRED_AND_FAILED";
        }
        if (oldSent) return "POST_SEND_CLOSE";
        return "NOT_ATTRIBUTABLE";
    }

    private void writeArtifacts(EventRecorder recorder, List<Map<String, Object>> cycles) throws IOException {
        Path root = Path.of("build", "experiment-1-16");
        Files.createDirectories(root);
        ObjectMapper mapper = new ObjectMapper();
        Files.write(root.resolve("experiment-1-16-events.jsonl"), recorder.jsonLines(mapper),
                StandardCharsets.UTF_8);
        Files.writeString(root.resolve("experiment-1-16-cycles.json"),
                mapper.writerWithDefaultPrettyPrinter().writeValueAsString(cycles), StandardCharsets.UTF_8);

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("configuredCycles", CYCLES);
        summary.put("completedCycles", cycles.size());
        summary.put("attribution", ATTRIBUTION);
        summary.put("classificationCounts", counts(cycles, "classification"));
        summary.put("internalRetryCounts", counts(cycles, "internalRetryAttribution"));
        summary.put("clientCloseFutureObserved", cycles.stream()
                .filter(row -> Boolean.TRUE.equals(row.get("clientCloseFutureObserved"))).count());
        summary.put("raceStartedBeforeMockCloseCompleted", cycles.stream()
                .filter(row -> Boolean.TRUE.equals(row.get("raceStartedBeforeMockCloseCompleted"))).count());
        summary.put("duplicateMockHandlerRequests", recorder.mockHandlerCounts().values().stream()
                .filter(count -> count != 1).count());
        summary.put("unobservableWithCurrentHook", Arrays.asList("DIRECT_TRANSPORT_RETRY_HOOK",
                "TCP_FIN_OR_RST_PACKET_FLAG", "DIRECT_REQUEST_BINDING_BEFORE_ACQUIRE"));
        Files.writeString(root.resolve("experiment-1-16-summary.json"),
                mapper.writerWithDefaultPrettyPrinter().writeValueAsString(summary), StandardCharsets.UTF_8);

        List<String> csv = new ArrayList<>();
        csv.add("cycleId,aChannelId,bRequestId,bChannelId,cRequestId,cFinalChannelId,aToBNormalReuse,raceStartedBeforeMockCloseCompleted,clientCloseFutureObserved,oldChannelAcquiredByC,oldChannelSentByC,newChannelAcquiredByC,nextFinalChannelNew,cSuccess,cError,cMockHandlerCount,classification,internalRetryAttribution,mockCloseInitiated,mockCloseFutureCompleted,clientCloseFutureCompleted,cAcquire,cRequestSent");
        for (Map<String, Object> cycle : cycles) csv.add(csvRow(cycle));
        Files.write(root.resolve("experiment-1-16-timeline.csv"), csv, StandardCharsets.UTF_8);

        Map<String, Object> validity = new LinkedHashMap<>();
        validity.put("verdict", "VALID");
        validity.put("cycles", cycles.size());
        validity.put("clientCloseFutureObserved", CYCLES);
        validity.put("raceStartedBeforeMockCloseCompleted", CYCLES);
        validity.put("productionLifecycleChanged", false);
        validity.put("directRequestBinding", "DIRECT_REQUEST_BINDING_NOT_AVAILABLE");
        validity.put("deterministicAttribution", ATTRIBUTION);
        Files.writeString(root.resolve("experiment-1-16-validity.json"),
                mapper.writerWithDefaultPrettyPrinter().writeValueAsString(validity), StandardCharsets.UTF_8);
    }

    private Map<String, Long> counts(List<Map<String, Object>> rows, String field) {
        Map<String, Long> result = new LinkedHashMap<>();
        for (Map<String, Object> row : rows) {
            String value = String.valueOf(row.get(field));
            result.put(value, result.getOrDefault(value, 0L) + 1);
        }
        return result;
    }

    private static String csvRow(Map<String, Object> values) {
        List<String> cells = new ArrayList<>();
        for (Object value : values.values()) {
            String text = String.valueOf(value == null ? "" : value).replace("\"", "\"\"");
            cells.add("\"" + text + "\"");
        }
        return String.join(",", cells);
    }

    private static void awaitEvent(EventRecorder recorder, String event, String requestId, String channelId)
            throws InterruptedException {
        long deadline = System.nanoTime() + WAIT.toNanos();
        while (System.nanoTime() < deadline) {
            if (recorder.hasEvent(event, requestId, channelId)) return;
            Thread.sleep(5);
        }
        throw new AssertionError("missing event " + event + " request=" + requestId + " channel=" + channelId);
    }

    private static void awaitEventForChannel(EventRecorder recorder, String event, String channelId)
            throws InterruptedException {
        long deadline = System.nanoTime() + WAIT.toNanos();
        while (System.nanoTime() < deadline) {
            if (recorder.hasEventForChannel(event, channelId)) return;
            Thread.sleep(5);
        }
        throw new AssertionError("missing event " + event + " channel=" + channelId);
    }

    private static long updateLease(Channel channel, ConnectionObserver.State state) {
        AtomicLong sequence = channel.attr(LEASE_SEQUENCE).get();
        if (sequence == null) {
            sequence = new AtomicLong();
            channel.attr(LEASE_SEQUENCE).set(sequence);
        }
        if (state == ConnectionObserver.State.CONFIGURED && sequence.get() == 0) {
            channel.attr(RELEASED).set(false);
            return sequence.incrementAndGet();
        }
        if (state == ConnectionObserver.State.ACQUIRED
                && (sequence.get() == 0 || Boolean.TRUE.equals(channel.attr(RELEASED).get()))) {
            channel.attr(RELEASED).set(false);
            return sequence.incrementAndGet();
        }
        if (state == ConnectionObserver.State.RELEASED) channel.attr(RELEASED).set(true);
        return sequence.get();
    }

    private static Long lease(Channel channel) {
        AtomicLong sequence = channel.attr(LEASE_SEQUENCE).get();
        return sequence == null ? null : sequence.get();
    }

    private static final class RaceGate {
        private final Sinks.One<Void> closeInitiated = Sinks.one();

        void openAtCloseInitiation() {
            closeInitiated.tryEmitEmpty();
        }

        void awaitCloseInitiated() {
            closeInitiated.asMono().block(WAIT);
        }
    }

    private static final class RequestResult {
        private final String requestId;
        private final String attemptId;
        private final String channelId;
        private final boolean success;
        private final String body;
        private final String errorClass;

        private RequestResult(String requestId, String attemptId, String channelId, boolean success,
                String body, String errorClass) {
            this.requestId = requestId;
            this.attemptId = attemptId;
            this.channelId = channelId;
            this.success = success;
            this.body = body;
            this.errorClass = errorClass;
        }
    }

    private static final class EventRecorder {
        private final List<Map<String, Object>> events = new CopyOnWriteArrayList<>();
        private final Map<String, Integer> mockHandlerCounts = new ConcurrentHashMap<>();
        private volatile String activeRequestId;
        private volatile String activeAttemptId;

        void beginSingleFlightRequest(String requestId, String attemptId) {
            activeRequestId = requestId;
            activeAttemptId = attemptId;
        }

        String requestIdFor(Channel channel) {
            String bound = channel.attr(LAST_REQUEST_ID).get();
            return bound == null ? activeRequestId : bound;
        }

        String attemptIdFor(Channel channel) {
            String bound = channel.attr(LAST_ATTEMPT_ID).get();
            return bound == null ? activeAttemptId : bound;
        }

        void incrementMockHandler(String requestId) {
            mockHandlerCounts.merge(requestId, 1, Integer::sum);
        }

        Map<String, Integer> mockHandlerCounts() {
            return mockHandlerCounts;
        }

        void record(String event, String requestId, String attemptId, Long lease, Channel channel, String source) {
            Instant now = Instant.now();
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("timestampEpochNanos", now.getEpochSecond() * 1_000_000_000L + now.getNano());
            row.put("timestampEpochMillis", now.toEpochMilli());
            row.put("event", event);
            row.put("requestId", requestId);
            row.put("attemptId", attemptId);
            row.put("retryOfAttemptId", null);
            row.put("leaseId", lease == null || channel == null ? null : channel.id().asLongText() + "-L" + lease);
            row.put("channelId", channel == null ? null : channel.id().asLongText());
            row.put("localAddress", channel == null ? null : String.valueOf(channel.localAddress()));
            row.put("remoteAddress", channel == null ? null : String.valueOf(channel.remoteAddress()));
            row.put("socketTuple", channel == null ? null : channel.localAddress() + ">" + channel.remoteAddress());
            row.put("stage", STAGE);
            row.put("thread", Thread.currentThread().getName());
            row.put("source", source);
            events.add(row);
        }

        boolean hasEvent(String event, String requestId, String channelId) {
            return events.stream().anyMatch(row -> event.equals(row.get("event"))
                    && (requestId == null || requestId.equals(row.get("requestId")))
                    && (channelId == null || channelId.equals(row.get("channelId"))));
        }

        boolean hasEventForChannel(String event, String channelId) {
            return hasEvent(event, null, channelId);
        }

        List<Map<String, Object>> events(String event, String requestId) {
            List<Map<String, Object>> result = new ArrayList<>();
            for (Map<String, Object> row : events) {
                if (event.equals(row.get("event")) && requestId.equals(row.get("requestId"))) result.add(row);
            }
            return result;
        }

        String lastChannel(String event, String requestId) {
            Map<String, Object> latest = events(event, requestId).stream()
                    .max(Comparator.comparingLong(row -> (Long) row.get("timestampEpochNanos"))).orElse(null);
            return latest == null ? null : (String) latest.get("channelId");
        }

        Long eventTime(String event, String requestId) {
            return events(event, requestId).stream()
                    .map(row -> (Long) row.get("timestampEpochNanos")).min(Long::compareTo).orElse(null);
        }

        Long eventTimeForChannel(String event, String channelId) {
            return events.stream().filter(row -> event.equals(row.get("event"))
                    && channelId.equals(row.get("channelId"))).map(row -> (Long) row.get("timestampEpochNanos"))
                    .min(Long::compareTo).orElse(null);
        }

        boolean before(String firstEvent, String firstRequestId, String secondEvent, String secondRequestId) {
            Long first = eventTime(firstEvent, firstRequestId);
            Long second = eventTime(secondEvent, secondRequestId);
            return first != null && second != null && first < second;
        }

        boolean before(String firstEvent, String firstChannelId, String secondEvent, String secondRequestId,
                boolean byChannel) {
            Long first = eventTimeForChannel(firstEvent, firstChannelId);
            Long second = eventTime(secondEvent, secondRequestId);
            return first != null && second != null && first < second;
        }

        int count(String event, String requestId, String ignored) {
            return (int) events.stream().filter(row -> event.equals(row.get("event"))).count();
        }

        List<String> jsonLines(ObjectMapper mapper) throws IOException {
            List<String> lines = new ArrayList<>();
            for (Map<String, Object> event : events) lines.add(mapper.writeValueAsString(event));
            return lines;
        }
    }
}
