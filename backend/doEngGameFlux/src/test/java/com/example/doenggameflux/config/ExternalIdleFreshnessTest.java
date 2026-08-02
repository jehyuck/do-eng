package com.example.doenggameflux.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.netty.DisposableServer;
import reactor.netty.http.client.HttpClient;
import reactor.netty.http.server.HttpServer;
import reactor.netty.resources.ConnectionProvider;

class ExternalIdleFreshnessTest {

    @Test
    void positiveMaxIdleTimeReplacesExpiredIdleConnection() throws Exception {
        DisposableServer server = fastServer();
        ConnectionProvider provider = provider(500);
        try {
            List<String> channels = new CopyOnWriteArrayList<>();
            HttpClient client = observedClient(provider, channels);

            assertEquals("ok", get(client, server, "/fast", Duration.ofSeconds(5)));
            Thread.sleep(800);
            assertEquals("ok", get(client, server, "/fast", Duration.ofSeconds(5)));

            assertEquals(2, channels.size());
            assertNotEquals(channels.get(0), channels.get(1));
        } finally {
            provider.disposeLater().block(Duration.ofSeconds(5));
            server.disposeNow();
        }
    }

    @Test
    void disabledMaxIdleTimePreservesExistingReuseSemantics() throws Exception {
        DisposableServer server = fastServer();
        ConnectionProvider provider = provider(0);
        try {
            List<String> channels = new CopyOnWriteArrayList<>();
            HttpClient client = observedClient(provider, channels);

            assertEquals("ok", get(client, server, "/fast", Duration.ofSeconds(5)));
            Thread.sleep(800);
            assertEquals("ok", get(client, server, "/fast", Duration.ofSeconds(5)));

            assertEquals(2, channels.size());
            assertEquals(channels.get(0), channels.get(1));
        } finally {
            provider.disposeLater().block(Duration.ofSeconds(5));
            server.disposeNow();
        }
    }

    @Test
    void maxIdleTimeDoesNotInterruptActiveTwoSecondResponse() {
        DisposableServer server = HttpServer.create()
                .port(0)
                .idleTimeout(Duration.ofSeconds(2))
                .route(routes -> routes.get("/slow", (request, response) ->
                        response.sendString(Mono.delay(Duration.ofSeconds(2)).map(ignored -> "ok"))))
                .bindNow();
        ConnectionProvider provider = provider(500);
        try {
            long startedAt = System.nanoTime();
            String body = get(HttpClient.create(provider), server, "/slow", Duration.ofSeconds(5));
            long elapsedMs = Duration.ofNanos(System.nanoTime() - startedAt).toMillis();

            assertEquals("ok", body);
            assertTrue(elapsedMs >= 1800, "response must remain active for the server delay");
        } finally {
            provider.disposeLater().block(Duration.ofSeconds(5));
            server.disposeNow();
        }
    }

    private DisposableServer fastServer() {
        return HttpServer.create()
                .port(0)
                .idleTimeout(Duration.ofSeconds(2))
                .route(routes -> routes.get("/fast", (request, response) ->
                        response.sendString(Mono.just("ok"))))
                .bindNow();
    }

    private ConnectionProvider provider(long maxIdleTimeMs) {
        ExternalServiceProperties properties = new ExternalServiceProperties();
        properties.setSharedPool(new ExternalServiceProperties.PoolSettings(4, 8));
        properties.setMaxIdleTimeMs(maxIdleTimeMs);
        return new ExternalHttpClientConfig().sharedConnectionProvider(
                properties, new DiagnosticProperties());
    }

    private HttpClient observedClient(ConnectionProvider provider, List<String> channels) {
        return HttpClient.create(provider)
                .doOnRequest((request, connection) ->
                        channels.add(connection.channel().id().asLongText()));
    }

    private String get(
            HttpClient client,
            DisposableServer server,
            String path,
            Duration timeout) {
        return client.get()
                .uri("http://127.0.0.1:" + server.port() + path)
                .responseSingle((response, body) -> body.asString())
                .block(timeout);
    }
}
