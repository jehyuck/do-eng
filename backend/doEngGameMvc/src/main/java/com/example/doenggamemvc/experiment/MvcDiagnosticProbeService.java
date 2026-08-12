package com.example.doenggamemvc.experiment;

import com.example.doenggamemvc.client.AiClient;
import com.example.doenggamemvc.client.TokenClient;
import com.example.doenggamemvc.dto.AiDecisionResult;
import com.example.doenggamemvc.storage.MissionImageStorage;
import com.example.doenggamemvc.util.ImagePayloadDecoder;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;

/** Experiment-only phase probe. It reuses the production outbound clients. */
@Profile("experiment")
@Service
public class MvcDiagnosticProbeService {

    private final AiClient aiClient;
    private final TokenClient tokenClient;
    private final MissionImageStorage storage;
    private final MvcAiRequestSerializationProbe serializationProbe;

    public MvcDiagnosticProbeService(
            AiClient aiClient,
            TokenClient tokenClient,
            MissionImageStorage storage,
            MvcAiRequestSerializationProbe serializationProbe) {
        this.aiClient = aiClient;
        this.tokenClient = tokenClient;
        this.storage = storage;
        this.serializationProbe = serializationProbe;
    }

    public Map<String, Object> probe(
            String mode,
            String image,
            String answer,
            String authorization,
            String runId,
            String requestId) {
        String effectiveMode = mode == null ? "INGRESS" : mode.trim().toUpperCase();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("mode", effectiveMode);
        result.put("runId", runId);
        result.put("imageChars", image == null ? 0 : image.length());

        switch (effectiveMode) {
            case "INGRESS":
                result.put("steps", new String[] {"JSON_DESERIALIZE"});
                return result;
            case "SERIALIZE_ONLY":
                result.putAll(serializationProbe.serialize(image, answer));
                result.put("mode", effectiveMode);
                result.put("runId", runId);
                return result;
            case "AI":
                result.put("ai", aiClient.decide(image, answer));
                result.put("steps", new String[] {"JSON_DESERIALIZE", "AI_HTTP"});
                return result;
            case "AI_DECODE":
                result.put("ai", aiClient.decide(image, answer));
                result.put("decodedBytes", ImagePayloadDecoder
                        .decodeDataUrlOrBase64(image).length);
                result.put("steps", new String[] {"JSON_DESERIALIZE", "AI_HTTP", "BASE64_DECODE"});
                return result;
            case "AI_STORAGE":
                return aiStorage(result, image, answer, runId, requestId);
            case "TOKEN_AI_STORAGE":
                if (authorization == null || authorization.isBlank()) {
                    throw new IllegalArgumentException("Authorization is required for TOKEN_AI_STORAGE");
                }
                result.put("memberId", tokenClient.confirm(authorization));
                return aiStorage(result, image, answer, runId, requestId);
            case "FULL":
                result.put("productionEndpoint", "/game/face");
                result.put("steps", new String[] {"USE_PRODUCTION_ENDPOINT"});
                return result;
            default:
                throw new IllegalArgumentException("Unsupported diagnostic mode: " + effectiveMode);
        }
    }

    private Map<String, Object> aiStorage(
            Map<String, Object> result,
            String image,
            String answer,
            String runId,
            String requestId) {
        AiDecisionResult ai = aiClient.decide(image, answer);
        byte[] decoded = ImagePayloadDecoder.decodeDataUrlOrBase64(image);
        String key = storage.upload(
                "diagnostic/" + (runId == null ? "unknown" : runId) + "/"
                        + (requestId == null ? "unknown" : requestId) + ".jpeg",
                decoded);
        result.put("ai", ai);
        result.put("decodedBytes", decoded.length);
        result.put("storageKey", key);
        result.put("steps", new String[] {"AI_HTTP", "BASE64_DECODE", "STORAGE_HTTP"});
        return result;
    }
}
