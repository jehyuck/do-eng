package com.example.doenggamemvc.experiment;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.doenggamemvc.client.AiClient;
import com.example.doenggamemvc.client.TokenClient;
import com.example.doenggamemvc.dto.AiDecisionResult;
import com.example.doenggamemvc.storage.MissionImageStorage;
import java.util.Map;
import java.util.Arrays;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MvcDiagnosticProbeServiceTest {

    @Mock
    private AiClient aiClient;

    @Mock
    private TokenClient tokenClient;

    @Mock
    private MissionImageStorage storage;

    @Mock
    private MvcAiRequestSerializationProbe serializationProbe;

    private MvcDiagnosticProbeService service;

    @BeforeEach
    void setUp() {
        service = new MvcDiagnosticProbeService(
                aiClient, tokenClient, storage, serializationProbe);
    }

    @Test
    void ingressDoesNotCallExternalServices() {
        Map<String, Object> result = service.probe(
                "INGRESS", "aGVsbG8=", "happy", null, "run", "request");

        assertEquals("INGRESS", result.get("mode"));
        verify(aiClient, never()).decide(anyString(), anyString());
        verify(tokenClient, never()).confirm(anyString());
        verify(storage, never()).upload(anyString(), any());
    }

    @Test
    void aiDecodeAddsOnlyTheDecoderAfterAi() {
        AiDecisionResult decision = new AiDecisionResult();
        decision.setResult(true);
        when(aiClient.decide(anyString(), anyString())).thenReturn(decision);

        Map<String, Object> result = service.probe(
                "AI_DECODE", "aGVsbG8=", "happy", null, "run", "request");

        assertEquals(5, result.get("decodedBytes"));
        verify(aiClient).decide("aGVsbG8=", "happy");
        verify(storage, never()).upload(anyString(), any());
    }

    @Test
    void tokenAiStorageUsesProductionClientsInOrder() {
        AiDecisionResult decision = new AiDecisionResult();
        decision.setResult(true);
        when(tokenClient.confirm("Bearer token")).thenReturn(15L);
        when(aiClient.decide(anyString(), anyString())).thenReturn(decision);
        when(storage.upload(anyString(), any())).thenReturn("diagnostic/run/request.jpeg");

        Map<String, Object> result = service.probe(
                "TOKEN_AI_STORAGE", "aGVsbG8=", "happy", "Bearer token", "run", "request");

        assertEquals(15L, result.get("memberId"));
        assertEquals("diagnostic/run/request.jpeg", result.get("storageKey"));
        verify(tokenClient).confirm("Bearer token");
        verify(aiClient).decide("aGVsbG8=", "happy");
        verify(storage).upload(eq("diagnostic/run/request.jpeg"), argThat(bytes -> Arrays.equals(bytes, "hello".getBytes())));
    }

    @Test
    void tokenModeRequiresAuthorization() {
        assertThrows(IllegalArgumentException.class, () -> service.probe(
                "TOKEN_AI_STORAGE", "aGVsbG8=", "happy", null, "run", "request"));
    }

    @Test
    void serializeOnlyDoesNotCallExternalServices() {
        when(serializationProbe.serialize("aGVsbG8=", "happy"))
                .thenReturn(Map.of(
                        "result", true,
                        "serialization", Map.of("serializedBytes", 42)));

        Map<String, Object> result = service.probe(
                "SERIALIZE_ONLY", "aGVsbG8=", "happy", null, "run", "request");

        assertEquals(true, result.get("result"));
        verify(serializationProbe).serialize("aGVsbG8=", "happy");
        verify(aiClient, never()).decide(anyString(), anyString());
        verify(tokenClient, never()).confirm(anyString());
        verify(storage, never()).upload(anyString(), any());
    }
}
