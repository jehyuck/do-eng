package com.example.doenggameflux.experiment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.netty.channel.Channel;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.util.AttributeKey;
import java.io.IOException;
import java.net.SocketAddress;
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
import reactor.netty.Connection;
import reactor.netty.ConnectionObserver;
import reactor.netty.ByteBufFlux;
import reactor.netty.DisposableServer;
import reactor.netty.http.client.HttpClient;
import reactor.netty.http.server.HttpServer;
import reactor.netty.resources.ConnectionProvider;

/**
 * Test-only Experiment 1-15 lifecycle correlation harness.
 *
 * <p>It intentionally uses one in-flight request and one local pooled connection. This is not a
 * capacity test and does not alter application lifecycle configuration.</p>
 */
class DeterministicConnectionLifecycleCorrelationTest {

    private static final int CYCLES = 8;
    private static final Duration WAIT = Duration.ofSeconds(5);
    private static final String STAGE = "AI";
    private static final String ATTRIBUTION = "DETERMINISTIC_SINGLE_FLIGHT_ATTRIBUTION_USED";
    private static final AttributeKey<AtomicLong> LEASE_SEQUENCE =
            AttributeKey.valueOf("exp115.leaseSequence");
    private static final AttributeKey<String> LAST_REQUEST_ID =
            AttributeKey.valueOf("exp115.lastRequestId");
    private static final AttributeKey<String> LAST_ATTEMPT_ID =
            AttributeKey.valueOf("exp115.lastAttemptId");
    private static final AttributeKey<Boolean> RELEASED =
            AttributeKey.valueOf("exp115.released");

    @Test
    void correlatesEightSingleFlightConnectionCyclesWithoutChangingProductionLifecycle() throws Exception {
        EventRecorder recorder = new EventRecorder();
        DisposableServer server = server(recorder);
        ConnectionProvider provider = ConnectionProvider.builder("exp115-test-provider")
                .maxConnections(1)
                .pendingAcquireMaxCount(1)
                .pendingAcquireTimeout(Duration.ofSeconds(2))
                .build();
        try {
            HttpClient client = observedClient(provider, recorder);
            List<Map<String, Object>> cycles = new ArrayList<>();

            for (int cycle = 1; cycle <= CYCLES; cycle++) {
                String prefix = "EXP115-C" + cycle;
                RequestResult first = post(client, server, recorder, prefix + "-A", false);
                await(recorder, "POOL_RELEASE_OBSERVED", first.requestId, null);

                RequestResult reused = post(client, server, recorder, prefix + "-B", true);
                await(recorder, "POOL_RELEASE_OBSERVED", reused.requestId, null);
                await(recorder, "MOCK_FIN_SENT", reused.requestId, null);
                await(recorder, "MOCK_SOCKET_CLOSE_COMPLETED", reused.requestId, null);

                RequestResult reopened = post(client, server, recorder, prefix + "-C", false);
                await(recorder, "POOL_RELEASE_OBSERVED", reopened.requestId, null);

                assertEquals(first.channelId, reused.channelId,
                        "Gate A requires normal pooled reuse before test-only peer close");
                assertNotEquals(reused.channelId, reopened.channelId,
                        "Gate B requires the peer-closed channel not be reused");

                cycles.add(cycleRow(cycle, first, reused, reopened, recorder));
            }

            assertEquals(CYCLES * 3, recorder.mockHandlerCounts().size());
            assertTrue(recorder.mockHandlerCounts().values().stream().allMatch(count -> count == 1),
                    "Gate C: one mock handler arrival per logical request");

            writeArtifacts(recorder, cycles);

            assertEquals(CYCLES, cycles.size());
            assertTrue(cycles.stream().allMatch(row -> Boolean.TRUE.equals(row.get("normalReuse"))));
            assertTrue(cycles.stream().allMatch(row -> Boolean.TRUE.equals(row.get("peerCloseObserved"))));
            assertTrue(cycles.stream().allMatch(row -> Boolean.TRUE.equals(row.get("nextAcquireNewChannel"))));
        } finally {
            provider.disposeLater().block(WAIT);
            server.disposeNow();
        }
    }

    private DisposableServer server(EventRecorder recorder) {
        return HttpServer.create()
                .port(0)
                .doOnConnection(connection -> connection.addHandlerLast(
                        "exp115-server-close", new ChannelInboundHandlerAdapter() {
                            @Override
                            public void channelInactive(ChannelHandlerContext context) throws Exception {
                                recorder.record("MOCK_SOCKET_INACTIVE", null, null, lease(context.channel()),
                                        context.channel(), "mock-server");
                                super.channelInactive(context);
                            }
                        }))
                .route(routes -> routes.post("/face", (request, response) -> {
                    String requestId = request.requestHeaders().get("X-Exp15-Request-Id");
                    String attemptId = request.requestHeaders().get("X-Exp15-Attempt-Id");
                    boolean closeAfterResponse = request.uri().contains("closeAfterResponse=true");
                    Connection[] connection = new Connection[1];
                    response.withConnection(value -> connection[0] = value);
                    recorder.incrementMockHandler(requestId);
                    recorder.record("MOCK_REQUEST_RECEIVED", requestId, attemptId, null,
                            connection[0] == null ? null : connection[0].channel(), "mock-server");
                    return request.receive().aggregate().asString()
                            .doOnSuccess(body -> recorder.record("MOCK_REQUEST_BODY_COMPLETED",
                                    requestId, attemptId, null, connection[0].channel(), "mock-server"))
                            .then(Mono.defer(() -> {
                                recorder.record("MOCK_RESPONSE_STARTED", requestId, attemptId, null,
                                        connection[0].channel(), "mock-server");
                                response.header("X-Exp15-Request-Id", requestId);
                                response.header("X-Exp15-Attempt-Id", attemptId);
                                return response.sendString(Mono.just("{\"result\":true}"))
                                        .then()
                                        .doOnSuccess(ignored -> {
                                            recorder.record("MOCK_RESPONSE_FINISHED", requestId,
                                                    attemptId, null, connection[0].channel(), "mock-server");
                                            if (closeAfterResponse) {
                                                connection[0].channel().eventLoop().schedule(() -> {
                                                    recorder.record("MOCK_FIN_SENT", requestId, attemptId,
                                                            null, connection[0].channel(), "mock-server");
                                                    connection[0].channel().close().addListener(closeFuture ->
                                                            recorder.record("MOCK_SOCKET_CLOSE_COMPLETED",
                                                                    requestId, attemptId, null,
                                                                    connection[0].channel(), "mock-server"));
                                                }, 100, TimeUnit.MILLISECONDS);
                                            }
                                        });
                            }));
                }))
                .bindNow();
    }

    private HttpClient observedClient(ConnectionProvider provider, EventRecorder recorder) {
        return HttpClient.create(provider)
                .doOnConnected(connection -> connection.addHandlerFirst(
                        "exp115-client-inactive", new ChannelInboundHandlerAdapter() {
                            @Override
                            public void channelInactive(ChannelHandlerContext context) throws Exception {
                                recorder.record("CLIENT_CHANNEL_INACTIVE",
                                        context.channel().attr(LAST_REQUEST_ID).get(),
                                        context.channel().attr(LAST_ATTEMPT_ID).get(),
                                        lease(context.channel()), context.channel(), "client-channel-handler");
                                super.channelInactive(context);
                            }
                        }))
                .doOnRequest((request, connection) -> {
                    String requestId = request.requestHeaders().get("X-Exp15-Request-Id");
                    String attemptId = request.requestHeaders().get("X-Exp15-Attempt-Id");
                    connection.channel().attr(LAST_REQUEST_ID).set(requestId);
                    connection.channel().attr(LAST_ATTEMPT_ID).set(attemptId);
                    recorder.record("REQUEST_SENT", requestId, attemptId, lease(connection.channel()),
                            connection.channel(), "HttpClient.doOnRequest");
                })
                .doAfterRequest((request, connection) -> recorder.record("REQUEST_BODY_SENT",
                        request.requestHeaders().get("X-Exp15-Request-Id"),
                        request.requestHeaders().get("X-Exp15-Attempt-Id"), lease(connection.channel()),
                        connection.channel(), "HttpClient.doAfterRequest"))
                .doOnResponse((response, connection) -> recorder.record("CLIENT_RESPONSE_RECEIVED",
                        response.responseHeaders().get("X-Exp15-Request-Id"),
                        response.responseHeaders().get("X-Exp15-Attempt-Id"), lease(connection.channel()),
                        connection.channel(), "HttpClient.doOnResponse"))
                .doAfterResponseSuccess((response, connection) -> recorder.record(
                        "CLIENT_RESPONSE_BODY_COMPLETED",
                        response.responseHeaders().get("X-Exp15-Request-Id"),
                        response.responseHeaders().get("X-Exp15-Attempt-Id"), lease(connection.channel()),
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
                        } else if (state == State.DISCONNECTING) {
                            recorder.record("CLIENT_CHANNEL_INACTIVE", requestId, attemptId, sequence,
                                    channel, "ConnectionObserver.DISCONNECTING");
                        } else if ("[request_prepared]".equals(String.valueOf(state))) {
                            recorder.record("REQUEST_PREPARED", requestId, attemptId, sequence,
                                    channel, "ConnectionObserver.REQUEST_PREPARED");
                        }
                    }

                    @Override
                    public void onUncaughtException(Connection connection, Throwable error) {
                        recorder.record("REQUEST_FAILED", connection.channel().attr(LAST_REQUEST_ID).get(),
                                connection.channel().attr(LAST_ATTEMPT_ID).get(), lease(connection.channel()),
                                connection.channel(), "ConnectionObserver." + error.getClass().getSimpleName());
                    }
                });
    }

    private RequestResult post(
            HttpClient client,
            DisposableServer server,
            EventRecorder recorder,
            String requestId,
            boolean closeAfterResponse) {
        String attemptId = requestId + "-A1";
        recorder.beginSingleFlightRequest(requestId, attemptId);
        recorder.record("LOGICAL_REQUEST_CREATED", requestId, attemptId, null, null, ATTRIBUTION);
        String body = client.headers(headers -> {
                    headers.set("X-Exp15-Request-Id", requestId);
                    headers.set("X-Exp15-Attempt-Id", attemptId);
                })
                .post()
                .uri("http://127.0.0.1:" + server.port() + "/face?closeAfterResponse=" + closeAfterResponse)
                .send(ByteBufFlux.fromString(Mono.just("{\"image\":\"fixture\"}")))
                .responseSingle((response, content) -> content.asString())
                .doOnSuccess(result -> recorder.record("REQUEST_SUCCEEDED", requestId, attemptId,
                        null, null, "client-responseSingle"))
                .block(WAIT);
        Map<String, Object> sent = recorder.last("REQUEST_SENT", requestId);
        if (sent == null || sent.get("channelId") == null) {
            throw new AssertionError("request did not expose a client channel: " + requestId);
        }
        return new RequestResult(requestId, attemptId, (String) sent.get("channelId"), body);
    }

    private Map<String, Object> cycleRow(
            int cycle,
            RequestResult first,
            RequestResult reused,
            RequestResult reopened,
            EventRecorder recorder) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("cycleId", cycle);
        row.put("requestId", reused.requestId);
        row.put("attemptId", reused.attemptId);
        row.put("leaseId", eventValue(recorder, "POOL_RELEASE_OBSERVED", reused.requestId, "leaseId"));
        row.put("channelId", reused.channelId);
        row.put("socketTuple", eventValue(recorder, "REQUEST_SENT", reused.requestId, "socketTuple"));
        row.put("mockResponseFinished", eventTime(recorder, "MOCK_RESPONSE_FINISHED", reused.requestId));
        row.put("clientResponseReceived", eventTime(recorder, "CLIENT_RESPONSE_RECEIVED", reused.requestId));
        row.put("clientBodyCompleted", eventTime(recorder, "CLIENT_RESPONSE_BODY_COMPLETED", reused.requestId));
        row.put("poolReleased", eventTime(recorder, "POOL_RELEASE_OBSERVED", reused.requestId));
        row.put("peerClose", eventTime(recorder, "MOCK_FIN_SENT", reused.requestId));
        row.put("channelInactive", eventTime(recorder, "CLIENT_CHANNEL_INACTIVE", reused.requestId));
        row.put("nextAcquire", eventTime(recorder, "POOL_CONNECTION_ACQUIRED", reopened.requestId));
        row.put("requestPrepared", eventTime(recorder, "REQUEST_PREPARED", reopened.requestId));
        row.put("requestSent", eventTime(recorder, "REQUEST_SENT", reopened.requestId));
        row.put("retryAttempt", null);
        row.put("retryChannel", null);
        row.put("mockHandlerCount", recorder.mockHandlerCounts().get(reused.requestId));
        row.put("normalReuse", first.channelId.equals(reused.channelId));
        row.put("peerCloseObserved", eventTime(recorder, "MOCK_FIN_SENT", reused.requestId) != null
                && eventTime(recorder, "MOCK_SOCKET_CLOSE_COMPLETED", reused.requestId) != null);
        row.put("nextAcquireNewChannel", !reused.channelId.equals(reopened.channelId));
        row.put("finalResult", eventTime(recorder, "CLIENT_CHANNEL_INACTIVE", reused.requestId) == null
                ? "SUCCESS_WITH_CLIENT_IDLE_CLOSE_UNOBSERVED" : "SUCCESS");
        return row;
    }

    private void writeArtifacts(EventRecorder recorder, List<Map<String, Object>> cycles) throws IOException {
        Path root = Path.of("build", "experiment-1-15");
        Files.createDirectories(root);
        ObjectMapper mapper = new ObjectMapper();
        Files.write(root.resolve("experiment-1-15-events.jsonl"), recorder.jsonLines(mapper),
                StandardCharsets.UTF_8);
        Files.writeString(root.resolve("experiment-1-15-cycles.json"),
                mapper.writerWithDefaultPrettyPrinter().writeValueAsString(cycles), StandardCharsets.UTF_8);

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("configuredCycles", CYCLES);
        summary.put("completedCycles", cycles.size());
        summary.put("attribution", ATTRIBUTION);
        summary.put("clientIdleCloseObservation", "NOT_AVAILABLE");
        summary.put("retryAttribution", "NOT_ATTRIBUTABLE");
        summary.put("retryExplanation", "The test does not induce a client-observed first failure; an internal retry cannot be attributed.");
        summary.put("timeDeltasMs", deltaSummary(recorder, cycles));
        summary.put("unobservableWithCurrentHook", Arrays.asList("POOL_ACQUIRE_REQUESTED",
                "TRANSPORT_RETRY_DECIDED", "TRANSPORT_RETRY_STARTED", "TRANSPORT_RETRY_SKIPPED",
                "CLIENT_CHANNEL_CLOSED", "MOCK_RST_SENT",
                "CAUSAL_REQUEST_PREPARED_TO_SEND_BOUNDARY"));
        Files.writeString(root.resolve("experiment-1-15-summary.json"),
                mapper.writerWithDefaultPrettyPrinter().writeValueAsString(summary), StandardCharsets.UTF_8);

        List<String> csv = new ArrayList<>();
        csv.add("cycleId,requestId,attemptId,leaseId,channelId,socketTuple,mockResponseFinished,clientResponseReceived,clientBodyCompleted,poolReleased,peerClose,channelInactive,nextAcquire,requestPrepared,requestSent,retryAttempt,retryChannel,mockHandlerCount,normalReuse,peerCloseObserved,nextAcquireNewChannel,finalResult");
        for (Map<String, Object> cycle : cycles) {
            csv.add(csvRow(cycle));
        }
        Files.write(root.resolve("experiment-1-15-timeline.csv"), csv, StandardCharsets.UTF_8);

        Map<String, Object> validity = new LinkedHashMap<>();
        validity.put("verdict", "VALID_WITH_LIMITED_CLIENT_CLOSE_ATTRIBUTION");
        validity.put("singleFlight", true);
        validity.put("configuredCycles", CYCLES);
        validity.put("completedCycles", cycles.size());
        validity.put("requestAttemptBindingComplete", true);
        validity.put("attemptLeaseBindingComplete", true);
        validity.put("directRequestBinding", "DIRECT_REQUEST_BINDING_NOT_AVAILABLE");
        validity.put("deterministicAttribution", ATTRIBUTION);
        validity.put("releaseObserved", true);
        validity.put("clientChannelInactiveAfterPeerClose", "NOT_AVAILABLE");
        validity.put("retryAttribution", "NOT_ATTRIBUTABLE");
        validity.put("duplicateMockHandlerRequests", 0);
        validity.put("productionLifecycleChanged", false);
        Files.writeString(root.resolve("experiment-1-15-validity.json"),
                mapper.writerWithDefaultPrettyPrinter().writeValueAsString(validity), StandardCharsets.UTF_8);
    }

    private Map<String, Object> deltaSummary(EventRecorder recorder, List<Map<String, Object>> cycles) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("T1_mockFinish_to_clientResponseReceived", summaries(recorder, cycles,
                "MOCK_RESPONSE_FINISHED", "CLIENT_RESPONSE_RECEIVED", "requestId"));
        result.put("T2_mockFinish_to_clientBodyCompleted", summaries(recorder, cycles,
                "MOCK_RESPONSE_FINISHED", "CLIENT_RESPONSE_BODY_COMPLETED", "requestId"));
        result.put("T3_mockFinish_to_poolRelease", summaries(recorder, cycles,
                "MOCK_RESPONSE_FINISHED", "POOL_RELEASE_OBSERVED", "requestId"));
        result.put("T4_poolRelease_to_peerFin", summaries(recorder, cycles,
                "POOL_RELEASE_OBSERVED", "MOCK_FIN_SENT", "requestId"));
        result.put("T5_peerFin_to_channelInactive", summaries(recorder, cycles,
                "MOCK_FIN_SENT", "CLIENT_CHANNEL_INACTIVE", "requestId"));
        result.put("T6_peerFin_to_nextAcquire", summaries(recorder, cycles,
                "MOCK_FIN_SENT", "POOL_CONNECTION_ACQUIRED", "nextRequestId"));
        result.put("T7_nextAcquire_to_requestPrepared", notAvailable());
        result.put("T8_requestPrepared_to_requestSent", notAvailable());
        result.put("T9_firstFailure_to_retryAcquire", notAvailable());
        return result;
    }

    private Map<String, Object> summaries(
            EventRecorder recorder, List<Map<String, Object>> cycles,
            String startEvent, String endEvent, String keyType) {
        List<Long> values = new ArrayList<>();
        int missing = 0;
        for (Map<String, Object> cycle : cycles) {
            String requestId = "nextRequestId".equals(keyType)
                    ? "EXP115-C" + cycle.get("cycleId") + "-C" : (String) cycle.get("requestId");
            Long start = eventTime(recorder, startEvent,
                    "nextRequestId".equals(keyType) && "POOL_CONNECTION_ACQUIRED".equals(startEvent)
                            ? requestId : (String) cycle.get("requestId"));
            Long end = eventTime(recorder, endEvent, requestId);
            if (start == null || end == null) {
                missing++;
            } else {
                values.add(TimeUnit.NANOSECONDS.toMillis(end - start));
            }
        }
        if (values.isEmpty()) return notAvailable();
        Collections.sort(values);
        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("count", values.size());
        summary.put("min", values.get(0));
        summary.put("median", values.get(values.size() / 2));
        summary.put("p95", values.get((int) Math.ceil(values.size() * 0.95) - 1));
        summary.put("max", values.get(values.size() - 1));
        summary.put("missingCount", missing);
        summary.put("attributionLevel", ATTRIBUTION);
        return summary;
    }

    private Map<String, Object> notAvailable() {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("count", 0);
        value.put("missingCount", CYCLES);
        value.put("attributionLevel", "UNOBSERVABLE_WITH_CURRENT_HOOK");
        return value;
    }

    private static String csvRow(Map<String, Object> values) {
        List<String> cells = new ArrayList<>();
        for (Object value : values.values()) {
            String text = String.valueOf(value == null ? "" : value).replace("\"", "\"\"");
            cells.add("\"" + text + "\"");
        }
        return String.join(",", cells);
    }

    private static Long eventTime(EventRecorder recorder, String event, String requestId) {
        Map<String, Object> row = recorder.first(event, requestId);
        return row == null ? null : (Long) row.get("timestampEpochNanos");
    }

    private static Object eventValue(EventRecorder recorder, String event, String requestId, String field) {
        Map<String, Object> row = recorder.first(event, requestId);
        return row == null ? null : row.get(field);
    }

    private static void await(EventRecorder recorder, String event, String requestId, String channelId)
            throws InterruptedException {
        long deadline = System.nanoTime() + WAIT.toNanos();
        while (System.nanoTime() < deadline) {
            Map<String, Object> row = recorder.first(event, requestId);
            if (row != null && (channelId == null || channelId.equals(row.get("channelId")))) return;
            Thread.sleep(5);
        }
        throw new AssertionError("missing lifecycle event " + event + " for " + requestId
                + "; observed=" + recorder.eventsFor(requestId));
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
        if (state == ConnectionObserver.State.ACQUIRED) {
            if (sequence.get() == 0 || Boolean.TRUE.equals(channel.attr(RELEASED).get())) {
                channel.attr(RELEASED).set(false);
                return sequence.incrementAndGet();
            }
        }
        if (state == ConnectionObserver.State.RELEASED) channel.attr(RELEASED).set(true);
        return sequence.get();
    }

    private static Long lease(Channel channel) {
        AtomicLong sequence = channel.attr(LEASE_SEQUENCE).get();
        return sequence == null ? null : sequence.get();
    }

    private static final class RequestResult {
        private final String requestId;
        private final String attemptId;
        private final String channelId;
        private final String body;

        private RequestResult(String requestId, String attemptId, String channelId, String body) {
            this.requestId = requestId;
            this.attemptId = attemptId;
            this.channelId = channelId;
            this.body = body;
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

        Map<String, Object> first(String event, String requestId) {
            return events.stream()
                    .filter(row -> event.equals(row.get("event")) && requestId.equals(row.get("requestId")))
                    .min(Comparator.comparingLong(row -> (Long) row.get("timestampEpochNanos")))
                    .orElse(null);
        }

        Map<String, Object> last(String event, String requestId) {
            return events.stream()
                    .filter(row -> event.equals(row.get("event")) && requestId.equals(row.get("requestId")))
                    .max(Comparator.comparingLong(row -> (Long) row.get("timestampEpochNanos")))
                    .orElse(null);
        }

        List<String> eventsFor(String requestId) {
            List<String> names = new ArrayList<>();
            for (Map<String, Object> event : events) {
                if (requestId.equals(event.get("requestId"))) {
                    names.add(event.get("event") + "@" + event.get("source"));
                }
            }
            return names;
        }

        List<String> jsonLines(ObjectMapper mapper) throws IOException {
            List<String> lines = new ArrayList<>();
            for (Map<String, Object> event : events) lines.add(mapper.writeValueAsString(event));
            return lines;
        }
    }
}
