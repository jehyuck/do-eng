package com.example.doenggameflux.repository;

import com.example.doenggameflux.entity.Progress;
import java.time.LocalDateTime;
import org.springframework.data.r2dbc.repository.Modifying;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Mono;

public interface ProgressRepository extends ReactiveCrudRepository<Progress, Long> {
    Mono<Progress> getByMemberIdAndSceneId(long memberId, long sceneId);

    @Modifying
    @Query("UPDATE progress SET played_at = :now where id = :progressId")
    Mono<Integer> updateProgress(
            @Param("now") LocalDateTime now,
            @Param("progressId") long progressId);
}
