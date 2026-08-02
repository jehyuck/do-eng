package com.example.doenggameflux.component;

import io.netty.channel.Channel;
import io.netty.channel.ChannelDuplexHandler;
import io.netty.channel.ChannelHandlerContext;
import io.netty.handler.codec.http.HttpHeaders;
import io.netty.util.AttributeKey;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import reactor.netty.Connection;
import reactor.netty.ConnectionObserver;
import reactor.netty.http.client.HttpClient;
import reactor.netty.http.client.HttpClientRequest;
import reactor.netty.http.client.HttpClientResponse;

/** Observation-only HTTP and pooled-channel lifecycle callbacks. */
public final class TransportHttpClientObservation {

    private static final String HANDLER_NAME = "doeng-connection-lifecycle";
    private static final AttributeKey<AtomicLong> LEASE_SEQUENCE =
            AttributeKey.valueOf("doeng.connection.leaseSequence");
    private static final AttributeKey<Boolean> RELEASED =
            AttributeKey.valueOf("doeng.connection.released");
    private static final AttributeKey<String> CONNECTION_CLASS =
            AttributeKey.valueOf("doeng.connection.class");
    private static final AttributeKey<String> CREATED_AT =
            AttributeKey.valueOf("doeng.connection.createdAt");
    private static final AttributeKey<String> PROVIDER_NAME =
            AttributeKey.valueOf("doeng.connection.providerName");
    private static final AttributeKey<String> CURRENT_STAGE =
            AttributeKey.valueOf("doeng.connection.stage");
    private static final AttributeKey<RequestBinding> REQUEST_BINDING =
            AttributeKey.valueOf("doeng.connection.requestBinding");

    private TransportHttpClientObservation() {}

    public static HttpClient instrument(
            HttpClient client,
            String stage,
            String providerName,
            TransportDiagnosticLogger logger,
            boolean enabled) {
        if (!enabled) return client;

        Map<String, Long> started = new ConcurrentHashMap<>();
        HttpClient observed = client
                .doOnConnected(connection -> {
                    initialize(connection.channel(), providerName, stage);
                    if (connection.channel().pipeline().context(HANDLER_NAME) == null) {
                        connection.addHandlerLast(HANDLER_NAME, new LifecycleHandler(logger));
                    }
                })
                .doOnRequest((request, connection) -> {
                    Channel channel = connection.channel();
                    initialize(channel, providerName, stage);
                    channel.attr(CURRENT_STAGE).set(stage);
                    channel.attr(REQUEST_BINDING).set(null);
                    String requestId = request.requestHeaders().get("X-Experiment-Request-Id");
                    if (requestId != null) started.put(requestId, System.nanoTime());
                    bindAndLogIfAvailable(logger, stage, channel, request.requestHeaders());
                    logger.log(stage, "REQUEST", requestId, missionRunId(request), null,
                            channel.remoteAddress(), 0, Thread.currentThread().getName(), "REQUEST_SENT");
                })
                .doAfterRequest((request, connection) -> {
                    bindAndLogIfAvailable(
                            logger, stage, connection.channel(), request.requestHeaders());
                    event(logger, stage, "AFTER_REQUEST", request, connection, null, started,
                            "REQUEST_COMPLETE");
                })
                .doOnRequestError((request, error) ->
                        event(logger, stage, "REQUEST_ERROR", request, connection(request), error, started,
                                category(error, "REQUEST_SEND_ERROR")))
                .doOnResponse((response, connection) ->
                        event(logger, stage, "RESPONSE", response, connection, null, started,
                                "RESPONSE_RECEIVED"))
                .doAfterResponseSuccess((response, connection) ->
                        event(logger, stage, "AFTER_RESPONSE_SUCCESS", response, connection, null, started,
                                "RESPONSE_COMPLETE"))
                .doOnResponseError((response, error) ->
                        event(logger, stage, "RESPONSE_ERROR", response, connection(response), error, started,
                                category(error, "UNKNOWN_OUTBOUND")))
                .observe(new ConnectionObserver() {
                    @Override
                    public void onStateChange(Connection connection, State newState) {
                        Map<String, Object> details = applyState(
                                connection.channel(), newState, providerName, stage);
                        logger.logConnectionEvent(
                                stage, "CONNECTION_STATE", String.valueOf(newState), details, null);
                    }

                    @Override
                    public void onUncaughtException(Connection connection, Throwable error) {
                        Channel channel = connection.channel();
                        initialize(channel, providerName, stage);
                        logger.logConnectionEvent(stage, "EXCEPTION_CAUGHT", null,
                                connectionDetails(channel), error);
                        if (isPrematureClose(error)) {
                            logger.logConnectionEvent(stage, "PREMATURE_CLOSE", null,
                                    connectionDetails(channel), error);
                        }
                        logger.log(stage, "CONNECTION_ERROR", null, null, error,
                                channel.remoteAddress(), 0, Thread.currentThread().getName(),
                                category(error, "UNKNOWN_OUTBOUND"));
                    }
                });
        return observed;
    }

    static Map<String, Object> applyState(
            Channel channel,
            ConnectionObserver.State state,
            String providerName,
            String stage) {
        initialize(channel, providerName, stage);
        channel.attr(CURRENT_STAGE).set(stage);
        if (state == ConnectionObserver.State.CONFIGURED && leases(channel).get() == 0) {
            leases(channel).incrementAndGet();
            channel.attr(CONNECTION_CLASS).set("NEW_CHANNEL");
            channel.attr(RELEASED).set(false);
        } else if (state == ConnectionObserver.State.ACQUIRED) {
            long lease = leases(channel).incrementAndGet();
            boolean previouslyReleased = Boolean.TRUE.equals(channel.attr(RELEASED).get());
            channel.attr(CONNECTION_CLASS).set(
                    lease == 1 ? "NEW_CHANNEL" : previouslyReleased ? "REUSED_CHANNEL" : "UNKNOWN");
            channel.attr(RELEASED).set(false);
            channel.attr(REQUEST_BINDING).set(null);
        } else if (state == ConnectionObserver.State.RELEASED) {
            channel.attr(RELEASED).set(true);
        }
        return connectionDetails(channel);
    }

    static Map<String, Object> bindForTest(Channel channel, HttpHeaders headers) {
        bind(channel, headers);
        return connectionDetails(channel);
    }

    static RequestBinding bindingForTest(Channel channel) {
        return channel.attr(REQUEST_BINDING).get();
    }

    private static RequestBinding bind(Channel channel, HttpHeaders headers) {
        RequestBinding binding = new RequestBinding(
                headers.get("X-Experiment-Request-Id"),
                headers.get("X-Experiment-Run-Id"),
                headers.get("X-Mission-Run-Id"),
                leases(channel).get());
        channel.attr(REQUEST_BINDING).set(binding);
        return binding;
    }

    private static void bindAndLogIfAvailable(
            TransportDiagnosticLogger logger,
            String stage,
            Channel channel,
            HttpHeaders headers) {
        if (!"AI".equals(stage)) return;
        String requestId = headers.get("X-Experiment-Request-Id");
        if (requestId == null) return;
        RequestBinding current = channel.attr(REQUEST_BINDING).get();
        if (current != null && requestId.equals(current.requestId)) return;
        RequestBinding binding = bind(channel, headers);
        logger.logRequestChannelBound(
                binding.requestId,
                binding.runId,
                binding.missionRunId,
                connectionDetails(channel));
    }

    private static void event(
            TransportDiagnosticLogger logger,
            String stage,
            String phase,
            Object requestOrResponse,
            Connection connection,
            Throwable error,
            Map<String, Long> started,
            String category) {
        HttpHeaders headers = headers(requestOrResponse);
        String requestId = headers == null ? null : headers.getAsString("X-Experiment-Request-Id");
        RequestBinding binding = connection == null
                ? null : connection.channel().attr(REQUEST_BINDING).get();
        if (requestId == null && binding != null) requestId = binding.requestId;
        Long start = requestId == null ? null : started.get(requestId);
        long elapsed = start == null ? 0 : TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
        String missionRunId = headers == null ? null : headers.getAsString("X-Mission-Run-Id");
        if (missionRunId == null && binding != null) missionRunId = binding.missionRunId;
        logger.log(stage, phase, requestId, missionRunId, error,
                remote(connection), elapsed, Thread.currentThread().getName(), category);
        if (connection != null && error != null) {
            String connectionPhase = "REQUEST_ERROR".equals(phase)
                    ? "REQUEST_SEND_ERROR" : "RESPONSE_ERROR";
            logger.logConnectionEvent(stage, connectionPhase, null,
                    connectionDetails(connection.channel()), error);
            if (isPrematureClose(error)) {
                logger.logConnectionEvent(stage, "PREMATURE_CLOSE", null,
                        connectionDetails(connection.channel()), error);
            }
        }
        if (phase.startsWith("AFTER") && requestId != null) started.remove(requestId);
    }

    private static HttpHeaders headers(Object value) {
        if (value instanceof HttpClientRequest) {
            return ((HttpClientRequest) value).requestHeaders();
        }
        if (value instanceof HttpClientResponse) {
            return ((HttpClientResponse) value).responseHeaders();
        }
        return null;
    }

    private static Connection connection(Object value) {
        return value instanceof Connection ? (Connection) value : null;
    }

    private static void initialize(Channel channel, String providerName, String stage) {
        channel.attr(CREATED_AT).setIfAbsent(Instant.now().toString());
        channel.attr(PROVIDER_NAME).setIfAbsent(providerName);
        channel.attr(CURRENT_STAGE).set(stage);
        leases(channel);
    }

    private static AtomicLong leases(Channel channel) {
        AtomicLong current = channel.attr(LEASE_SEQUENCE).get();
        if (current != null) return current;
        AtomicLong created = new AtomicLong();
        if (channel.attr(LEASE_SEQUENCE).compareAndSet(null, created)) return created;
        return channel.attr(LEASE_SEQUENCE).get();
    }

    private static Map<String, Object> connectionDetails(Channel channel) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("channelIdShort", channel.id().asShortText());
        details.put("channelIdLong", channel.id().asLongText());
        address(details, "local", channel.localAddress());
        address(details, "remote", channel.remoteAddress());
        details.put("connectionProviderName", channel.attr(PROVIDER_NAME).get());
        details.put("createdAt", channel.attr(CREATED_AT).get());
        details.put("leaseSequence", leases(channel).get());
        details.put("connectionClass", channel.attr(CONNECTION_CLASS).get());
        return details;
    }

    private static void address(Map<String, Object> target, String prefix, SocketAddress address) {
        if (address instanceof InetSocketAddress) {
            InetSocketAddress inet = (InetSocketAddress) address;
            target.put(prefix + "Address", inet.getAddress() == null
                    ? inet.getHostString() : inet.getAddress().getHostAddress());
            target.put(prefix + "Port", inet.getPort());
        } else {
            target.put(prefix + "Address", address == null ? null : address.toString());
            target.put(prefix + "Port", null);
        }
    }

    private static String missionRunId(HttpClientRequest request) {
        return request.requestHeaders().get("X-Mission-Run-Id");
    }

    private static SocketAddress remote(Connection connection) {
        return connection == null ? null : connection.channel().remoteAddress();
    }

    private static boolean isPrematureClose(Throwable error) {
        Throwable current = error;
        int depth = 0;
        while (current != null && depth++ < 8) {
            if (current.getClass().getName().contains("PrematureCloseException")) return true;
            current = current.getCause();
        }
        return false;
    }

    private static String category(Throwable error, String fallback) {
        if (error == null) return fallback;
        String text = (error.getClass().getName() + " " + error.getMessage()).toLowerCase();
        if (text.contains("pending") || text.contains("acquire")) return "POOL_ACQUIRE_LIMIT";
        if (text.contains("timeout") && text.contains("connect")) return "CONNECT_TIMEOUT";
        if (text.contains("refused")) return "CONNECT_REFUSED";
        if (text.contains("premature") && text.contains("response")) {
            return "PREMATURE_CLOSE_DURING_RESPONSE";
        }
        if (text.contains("timeout")) return "RESPONSE_TIMEOUT";
        if (text.contains("cancel")) return "CANCELLED";
        return fallback;
    }

    static final class RequestBinding {
        final String requestId;
        final String runId;
        final String missionRunId;
        final long leaseSequence;

        RequestBinding(String requestId, String runId, String missionRunId, long leaseSequence) {
            this.requestId = requestId;
            this.runId = runId;
            this.missionRunId = missionRunId;
            this.leaseSequence = leaseSequence;
        }
    }

    private static final class LifecycleHandler extends ChannelDuplexHandler {
        private final TransportDiagnosticLogger logger;

        private LifecycleHandler(TransportDiagnosticLogger logger) {
            this.logger = logger;
        }

        @Override
        public void channelInactive(ChannelHandlerContext context) throws Exception {
            String stage = context.channel().attr(CURRENT_STAGE).get();
            logger.logConnectionEvent(stage, "CHANNEL_INACTIVE", null,
                    connectionDetails(context.channel()), null);
            super.channelInactive(context);
        }

        @Override
        public void exceptionCaught(ChannelHandlerContext context, Throwable cause) throws Exception {
            String stage = context.channel().attr(CURRENT_STAGE).get();
            logger.logConnectionEvent(stage, "EXCEPTION_CAUGHT", null,
                    connectionDetails(context.channel()), cause);
            super.exceptionCaught(context, cause);
        }
    }
}
