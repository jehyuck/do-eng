package com.example.doenggameflux.component;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;

import com.example.doenggameflux.config.TransportAttributionProperties;
import io.netty.channel.embedded.EmbeddedChannel;
import io.netty.handler.codec.http.DefaultHttpHeaders;
import java.util.Map;
import org.junit.jupiter.api.Test;
import reactor.netty.ConnectionObserver;
import reactor.netty.http.client.HttpClient;

class TransportConnectionLifecycleTest {

    @Test
    void firstLeaseIsNewAndLeaseAfterReleaseIsReused() {
        EmbeddedChannel channel = new EmbeddedChannel();
        try {
            TransportHttpClientObservation.applyState(
                    channel, ConnectionObserver.State.CONNECTED, "doeng-external", "AI");
            Map<String, Object> first = TransportHttpClientObservation.applyState(
                    channel, ConnectionObserver.State.ACQUIRED, "doeng-external", "AI");
            assertEquals(1L, first.get("leaseSequence"));
            assertEquals("NEW_CHANNEL", first.get("connectionClass"));

            TransportHttpClientObservation.applyState(
                    channel, ConnectionObserver.State.RELEASED, "doeng-external", "AI");
            Map<String, Object> second = TransportHttpClientObservation.applyState(
                    channel, ConnectionObserver.State.ACQUIRED, "doeng-external", "AI");
            assertEquals(2L, second.get("leaseSequence"));
            assertEquals("REUSED_CHANNEL", second.get("connectionClass"));
        } finally {
            channel.finishAndReleaseAll();
        }
    }

    @Test
    void requestIdentityBindsToCurrentChannelLease() {
        EmbeddedChannel channel = new EmbeddedChannel();
        try {
            TransportHttpClientObservation.applyState(
                    channel, ConnectionObserver.State.ACQUIRED, "doeng-external", "AI");
            DefaultHttpHeaders headers = new DefaultHttpHeaders();
            headers.set("X-Experiment-Request-Id", "request-1");
            headers.set("X-Experiment-Run-Id", "run-1");
            headers.set("X-Mission-Run-Id", "mission-1");

            TransportHttpClientObservation.bindForTest(channel, headers);
            TransportHttpClientObservation.RequestBinding binding =
                    TransportHttpClientObservation.bindingForTest(channel);

            assertEquals("request-1", binding.requestId);
            assertEquals("run-1", binding.runId);
            assertEquals("mission-1", binding.missionRunId);
            assertEquals(1L, binding.leaseSequence);
        } finally {
            channel.finishAndReleaseAll();
        }
    }

    @Test
    void diagnosticOffReturnsOriginalHttpClient() {
        HttpClient client = HttpClient.create();
        TransportAttributionProperties properties = new TransportAttributionProperties();
        TransportDiagnosticLogger logger = new TransportDiagnosticLogger(properties);

        assertSame(client, TransportHttpClientObservation.instrument(
                client, "AI", "doeng-external", logger, false));
    }
}
