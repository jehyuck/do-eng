package com.example.doenggamemvc.controller;

import com.example.doenggamemvc.client.AiClient;
import com.example.doenggamemvc.client.TokenClient;
import com.example.doenggamemvc.dto.AiDecisionResult;
import com.example.doenggamemvc.dto.ImageRequest;
import com.example.doenggamemvc.service.MissionCompletionService;
import com.example.doenggamemvc.util.ImagePayloadDecoder;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpStatusCodeException;

@RestController
public class MissionController {

    private final TokenClient tokenClient;
    private final AiClient aiClient;
    private final MissionCompletionService missionCompletionService;

    public MissionController(
            TokenClient tokenClient,
            AiClient aiClient,
            MissionCompletionService missionCompletionService) {
        this.tokenClient = tokenClient;
        this.aiClient = aiClient;
        this.missionCompletionService = missionCompletionService;
    }

    @GetMapping("/test")
    public String test() {
        return "안녕하세요";
    }

    @PostMapping("/game/face")
    public ResponseEntity<String> requestFaceAi(
            @RequestBody ImageRequest image,
            @RequestParam("answer") String answer,
            @RequestParam("sceneId") long sceneId,
            @RequestHeader(
                    value = HttpHeaders.AUTHORIZATION,
                    required = false)
            String authorization,
            @RequestHeader(
                    value = "X-Mission-Run-Id",
                    required = false)
            String missionRunId) {
        if (authorization == null) {
            return ResponseEntity
                    .status(HttpStatus.UNAUTHORIZED)
                    .body("JWT token Not Found");
        }
        String effectiveMissionRunId = normalizeMissionRunId(missionRunId);
        if (effectiveMissionRunId == null) {
            return ResponseEntity.badRequest().body("Invalid X-Mission-Run-Id");
        }

        try {
            long memberId = tokenClient.confirm(authorization);
            AiDecisionResult decision =
                    aiClient.decide(image.getImage(), answer);
            if (!decision.isResult()) {
                return ResponseEntity.ok("false");
            }

            byte[] decodedImage = ImagePayloadDecoder
                    .decodeDataUrlOrBase64(image.getImage());
            missionCompletionService.complete(
                    decodedImage,
                    sceneId,
                    memberId,
                    effectiveMissionRunId);
            return ResponseEntity.ok("true");
        } catch (HttpStatusCodeException error) {
            return ResponseEntity
                    .status(error.getStatusCode())
                    .body(error.getResponseBodyAsString());
        }
    }

    private String normalizeMissionRunId(String missionRunId) {
        if (missionRunId == null) {
            return UUID.randomUUID().toString();
        }
        String normalized = missionRunId.trim();
        if (normalized.isEmpty() || normalized.length() > 191) {
            return null;
        }
        return normalized;
    }
}
