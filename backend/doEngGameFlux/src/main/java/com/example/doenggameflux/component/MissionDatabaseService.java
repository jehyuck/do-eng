package com.example.doenggameflux.component;

import com.example.doenggameflux.entity.Picture;
import com.example.doenggameflux.entity.Progress;
import com.example.doenggameflux.repository.PictureRepository;
import com.example.doenggameflux.repository.ProgressRepository;
import java.time.LocalDateTime;
import lombok.RequiredArgsConstructor;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import reactor.core.publisher.Mono;

@Service
@RequiredArgsConstructor
public class MissionDatabaseService {

    private final ProgressRepository progressRepository;
    private final PictureRepository pictureRepository;
    private final DatabaseClient databaseClient;

    @Transactional
    public Mono<Boolean> saveCompletionIfFirst(
            String objectKey,
            long sceneId,
            long memberId,
            String missionRunId) {
        LocalDateTime completedAt = LocalDateTime.now();

        return databaseClient.sql(
                        "INSERT IGNORE INTO mission_completion "
                                + "(member_id, scene_id, mission_run_id, object_key, completed_at) "
                                + "VALUES (:memberId, :sceneId, :missionRunId, :objectKey, :completedAt)")
                .bind("memberId", memberId)
                .bind("sceneId", sceneId)
                .bind("missionRunId", missionRunId)
                .bind("objectKey", objectKey)
                .bind("completedAt", completedAt)
                .fetch()
                .rowsUpdated()
                .flatMap(claimed -> claimed == 0
                        ? Mono.just(false)
                        : saveClaimedCompletion(
                                objectKey,
                                sceneId,
                                memberId,
                                completedAt));
    }

    private Mono<Boolean> saveClaimedCompletion(
            String objectKey,
            long sceneId,
            long memberId,
            LocalDateTime completedAt) {
        return progressRepository.getByMemberIdAndSceneId(memberId, sceneId)
                .switchIfEmpty(progressRepository.save(
                        Progress.builder()
                                .memberId(memberId)
                                .sceneId(sceneId)
                                .playedAt(completedAt)
                                .build()))
                .flatMap(progress -> pictureRepository.save(
                                Picture.builder()
                                        .progressId(progress.getId())
                                        .image(objectKey)
                                        .createdAt(completedAt)
                                        .build())
                        .then(progressRepository.updateProgress(
                                completedAt,
                                progress.getId()))
                        .thenReturn(true));
    }
}
