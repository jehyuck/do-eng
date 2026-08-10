package com.example.doenggamemvc.service;

import com.example.doenggamemvc.storage.MissionImageStorage;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class MissionCompletionService {

    private final MissionImageStorage missionImageStorage;
    private final MissionDatabaseService missionDatabaseService;

    public MissionCompletionService(
            MissionImageStorage missionImageStorage,
            MissionDatabaseService missionDatabaseService) {
        this.missionImageStorage = missionImageStorage;
        this.missionDatabaseService = missionDatabaseService;
    }

    public void complete(
            byte[] image,
            long sceneId,
            long memberId,
            String missionRunId) {
        String objectKey = deterministicObjectKey(
                memberId,
                sceneId,
                missionRunId);
        String savedObjectKey = missionImageStorage.upload(objectKey, image);
        missionDatabaseService.saveCompletionIfFirst(
                savedObjectKey,
                sceneId,
                memberId,
                missionRunId);
    }

    private String deterministicObjectKey(
            long memberId,
            long sceneId,
            String missionRunId) {
        String source = memberId + ":" + sceneId + ":" + missionRunId;
        UUID id = UUID.nameUUIDFromBytes(
                source.getBytes(StandardCharsets.UTF_8));
        return "picture/" + id + ".jpeg";
    }
}
