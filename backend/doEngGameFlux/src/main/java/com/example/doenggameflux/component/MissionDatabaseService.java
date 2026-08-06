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
    private final StageObservation stageObservation;

    @Transactional
    public Mono<Boolean> saveCompletionIfFirst(
            String objectKey,
            long sceneId,
            long memberId,
            String missionRunId) {
        LocalDateTime completedAt = LocalDateTime.now();

        Mono<Long> claim = databaseClient.sql(
                        "INSERT IGNORE INTO mission_completion "
                                + "(member_id, scene_id, mission_run_id, object_key, completed_at) "
                                + "VALUES (:memberId, :sceneId, :missionRunId, :objectKey, :completedAt)")
                .bind("memberId", memberId)
                .bind("sceneId", sceneId)
                .bind("missionRunId", missionRunId)
                .bind("objectKey", objectKey)
                .bind("completedAt", completedAt)
                .fetch()
                .rowsUpdated();

        return stageObservation.observe("DB_CLAIM", claim)
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
        Mono<Progress> progressLookupOrCreate = progressRepository
                .getByMemberIdAndSceneId(memberId, sceneId)
                .switchIfEmpty(progressRepository.save(
                        Progress.builder()
                                .memberId(memberId)
                                .sceneId(sceneId)
                                .playedAt(completedAt)
                                .build()));

        return stageObservation.observe("DB_PROGRESS_LOOKUP_OR_CREATE", progressLookupOrCreate)
                .flatMap(progress -> {
                    Mono<Picture> pictureInsert = pictureRepository.save(
                            Picture.builder()
                                    .progressId(progress.getId())
                                    .image(objectKey)
                                    .createdAt(completedAt)
                                    .build());
                    Mono<Integer> progressUpdate = progressRepository.updateProgress(
                            completedAt,
                            progress.getId());

                    return stageObservation.observe("DB_PICTURE_INSERT", pictureInsert)
                            .then(stageObservation.observe("DB_PROGRESS_UPDATE", progressUpdate))
                            .thenReturn(true);
                });
    }
}
