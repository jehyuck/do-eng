package com.example.doenggameflux.component;

import java.net.SocketAddress;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import io.netty.handler.codec.http.HttpHeaders;
import reactor.netty.Connection;
import reactor.netty.ConnectionObserver;
import reactor.netty.http.client.HttpClient;
import reactor.netty.http.client.HttpClientRequest;
import reactor.netty.http.client.HttpClientResponse;

/** Adds only callbacks and context headers when the diagnostic flag is enabled. */
public final class TransportHttpClientObservation {

    private TransportHttpClientObservation() {}

    public static HttpClient instrument(
            HttpClient client,
            String stage,
            TransportDiagnosticLogger logger,
            boolean enabled) {
        if (!enabled) {
            return client;
        }
        Map<String, Long> started = new ConcurrentHashMap<>();
        Map<Connection, String> requestByConnection = new ConcurrentHashMap<>();
        HttpClient observed = client
                .doOnRequest((request, connection) -> {
                    String requestId = request.requestHeaders().get("X-Experiment-Request-Id");
                    if (requestId != null) {
                        started.put(requestId, System.nanoTime());
                        requestByConnection.put(connection, requestId);
                    }
                    logger.log(stage, "REQUEST", requestId, missionRunId(request), null,
                            remote(connection), 0, Thread.currentThread().getName(), "REQUEST_SENT");
                })
                .doAfterRequest((request, connection) ->
                        event(logger, stage, "AFTER_REQUEST", request, connection, null, started,
                                requestByConnection, "REQUEST_COMPLETE"))
                .doOnRequestError((request, error) ->
                        event(logger, stage, "REQUEST_ERROR", request, null, error, started, requestByConnection,
                                category(error, "REQUEST_SEND_ERROR")))
                .doOnResponse((response, connection) ->
                        event(logger, stage, "RESPONSE", response, connection, null, started, requestByConnection,
                                "RESPONSE_RECEIVED"))
                .doAfterResponseSuccess((response, connection) ->
                        event(logger, stage, "AFTER_RESPONSE_SUCCESS", response, connection, null, started,
                                requestByConnection,
                                "RESPONSE_COMPLETE"))
                .doOnResponseError((response, error) ->
                        event(logger, stage, "RESPONSE_ERROR", response, null, error, started, requestByConnection,
                                category(error, "UNKNOWN_OUTBOUND")))
                .observe(new ConnectionObserver() {
                    @Override
                    public void onStateChange(Connection connection, State newState) {
                        logger.logState(stage, String.valueOf(newState), remote(connection),
                                Thread.currentThread().getName());
                    }

                    @Override
                    public void onUncaughtException(Connection connection, Throwable error) {
                        logger.log(stage, "CONNECTION_ERROR", null, null, error, remote(connection), 0,
                                Thread.currentThread().getName(), category(error, "UNKNOWN_OUTBOUND"));
                    }
                });
        return observed;
    }

    private static void event(
            TransportDiagnosticLogger logger,
            String stage,
            String phase,
            Object requestOrResponse,
            Connection connection,
            Throwable error,
            Map<String, Long> started,
            Map<Connection, String> requestByConnection,
            String category) {
        HttpHeaders headers = requestOrResponse instanceof HttpClientRequest
                ? ((HttpClientRequest) requestOrResponse).requestHeaders()
                : ((HttpClientResponse) requestOrResponse).responseHeaders();
        String requestId = headers.getAsString("X-Experiment-Request-Id");
        if (requestId == null && connection != null) {
            requestId = requestByConnection.get(connection);
        }
        Long start = requestId == null ? null : started.get(requestId);
        long elapsed = start == null ? 0 : TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start);
        logger.log(stage, phase, requestId, headers.getAsString("X-Mission-Run-Id"), error,
                remote(connection), elapsed, Thread.currentThread().getName(), category);
        if (phase.startsWith("AFTER") && requestId != null) {
            started.remove(requestId);
            if (connection != null) {
                requestByConnection.remove(connection);
            }
        }
    }

    private static String missionRunId(HttpClientRequest request) {
        return request.requestHeaders().get("X-Mission-Run-Id");
    }

    private static SocketAddress remote(Connection connection) {
        return connection == null || connection.channel() == null
                ? null : connection.channel().remoteAddress();
    }

    private static String category(Throwable error, String fallback) {
        if (error == null) return fallback;
        String text = (error.getClass().getName() + " " + error.getMessage()).toLowerCase();
        if (text.contains("pending") || text.contains("acquire")) return "POOL_ACQUIRE_LIMIT";
        if (text.contains("timeout") && text.contains("connect")) return "CONNECT_TIMEOUT";
        if (text.contains("refused")) return "CONNECT_REFUSED";
        if (text.contains("premature") && text.contains("response")) return "PREMATURE_CLOSE_DURING_RESPONSE";
        if (text.contains("timeout")) return "RESPONSE_TIMEOUT";
        if (text.contains("cancel")) return "CANCELLED";
        return fallback;
    }
}
