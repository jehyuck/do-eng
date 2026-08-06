package com.example.doenggameflux.component;

import com.example.doenggameflux.dispatcher.MissionExecutionContext;
import com.example.doenggameflux.s3.StorageDispatchRequest;
import com.example.doenggameflux.s3.StorageDispatcher;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
@RequiredArgsConstructor
public class DBComponentHttp {
    private final StorageDispatcher storageDispatcher;
    private final MissionDatabaseService missionDatabaseService;
    private final StageObservation stageObservation;
    private final AiOutboundAdmissionGate admissionGate;

    public Mono<String> saveData(
            MissionExecutionContext context,
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
                        () -> storageDispatcher.dispatch(
                                context,
                                new StorageDispatchRequest(objectKey, image))))
                .flatMap(savedObjectKey ->
                        stageObservation.observe("DB", missionDatabaseService.saveCompletionIfFirst(
                                savedObjectKey,
                                sceneId,
                                memberId,
                                missionRunId)))
                .thenReturn("true");
    }
}
