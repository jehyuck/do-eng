package com.example.doenggameflux.component;

import com.example.doenggameflux.s3.MissionImageStorage;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
@RequiredArgsConstructor
public class DBComponentHttp {
    private final MissionImageStorage missionImageStorage;
    private final MissionDatabaseService missionDatabaseService;
    private final StageObservation stageObservation;
    private final AiOutboundAdmissionGate admissionGate;

    public Mono<String> saveData(
            byte[] image,
            long sceneId,
            long memberId,
            String missionRunId) {
        String source = memberId + ":" + sceneId + ":" + missionRunId;
        String objectKey = "picture/"
                + UUID.nameUUIDFromBytes(source.getBytes(StandardCharsets.UTF_8))
                + ".jpeg";

        return stageObservation.observe("STORAGE", admissionGate.executeStage(
                        OutboundStage.STORAGE,
                        () -> missionImageStorage.upload(objectKey, image)))
                .flatMap(savedObjectKey ->
                        stageObservation.observe("DB", missionDatabaseService.saveCompletionIfFirst(
                                savedObjectKey,
                                sceneId,
                                memberId,
                                missionRunId)))
                .thenReturn("true");
    }
}
