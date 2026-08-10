package com.example.doenggamemvc.service;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MissionDatabaseService {

    private final JdbcTemplate jdbcTemplate;

    public MissionDatabaseService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public boolean saveCompletionIfFirst(
            String objectKey,
            long sceneId,
            long memberId,
            String missionRunId) {
        LocalDateTime completedAt = LocalDateTime.now();
        int claimed = jdbcTemplate.update(
                "INSERT IGNORE INTO mission_completion "
                        + "(member_id, scene_id, mission_run_id, object_key, completed_at) "
                        + "VALUES (?, ?, ?, ?, ?)",
                memberId,
                sceneId,
                missionRunId,
                objectKey,
                Timestamp.valueOf(completedAt));
        if (claimed == 0) {
            return false;
        }
        long progressId = findProgressId(memberId, sceneId)
                .orElseGet(() -> insertProgress(
                        memberId,
                        sceneId,
                        completedAt));

        jdbcTemplate.update(
                "INSERT INTO picture (created_at, image, progress_id) VALUES (?, ?, ?)",
                Timestamp.valueOf(completedAt),
                objectKey,
                progressId);
        jdbcTemplate.update(
                "UPDATE progress SET played_at = ? WHERE id = ?",
                Timestamp.valueOf(completedAt),
                progressId);
        return true;
    }

    private java.util.Optional<Long> findProgressId(
            long memberId,
            long sceneId) {
        List<Long> ids = jdbcTemplate.query(
                "SELECT id FROM progress WHERE member_id = ? AND scene_id = ? ORDER BY id LIMIT 1",
                (resultSet, rowNumber) -> resultSet.getLong("id"),
                memberId,
                sceneId);
        return ids.stream().findFirst();
    }

    private long insertProgress(
            long memberId,
            long sceneId,
            LocalDateTime completedAt) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        int updated = jdbcTemplate.update(connection -> {
            PreparedStatement statement = connection.prepareStatement(
                    "INSERT INTO progress (played_at, member_id, scene_id) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setTimestamp(1, Timestamp.valueOf(completedAt));
            statement.setLong(2, memberId);
            statement.setLong(3, sceneId);
            return statement;
        }, keyHolder);

        Number key = keyHolder.getKey();
        if (updated != 1 || key == null) {
            throw new IllegalStateException("Progress insert did not return an id");
        }
        return key.longValue();
    }
}
