package com.example.doenggameflux.component;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.r2dbc.core.DatabaseClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import reactor.core.publisher.Mono;

/** Verifies rollback at the actual Spring R2DBC transaction boundary. */
@SpringBootTest
@EnabledIfEnvironmentVariable(named = "DOENG_ATOMICITY_DB_URL", matches = ".+")
class MissionDatabaseServiceAtomicityIntegrationTest {

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.r2dbc.url", () -> System.getenv("DOENG_ATOMICITY_DB_URL"));
        registry.add("spring.r2dbc.username", () -> System.getenv().getOrDefault("DOENG_ATOMICITY_DB_USER", "test"));
        registry.add("spring.r2dbc.password", () -> System.getenv().getOrDefault("DOENG_ATOMICITY_DB_PASSWORD", "test"));
        registry.add("spring.r2dbc.pool.enabled", () -> "false");
        registry.add("cloud.aws.credentials.accessKey", () -> "test");
        registry.add("cloud.aws.credentials.secretKey", () -> "test");
        registry.add("cloud.aws.s3.bucket", () -> "test");
        registry.add("cloud.aws.region.static", () -> "ap-northeast-2");
    }

    @Autowired
    private MissionDatabaseService service;

    @Autowired
    private DatabaseClient databaseClient;

    @BeforeEach
    void resetSchema() {
        execute("DROP TABLE IF EXISTS picture").then(execute("DROP TABLE IF EXISTS mission_completion"))
                .then(execute("DROP TABLE IF EXISTS progress"))
                .then(execute("CREATE TABLE progress (id BIGINT AUTO_INCREMENT PRIMARY KEY, played_at DATETIME(6) NOT NULL, member_id BIGINT NOT NULL, scene_id BIGINT NOT NULL)"))
                .then(execute("CREATE TABLE mission_completion (member_id BIGINT NOT NULL, scene_id BIGINT NOT NULL, mission_run_id VARCHAR(191) NOT NULL, object_key VARCHAR(255) NOT NULL, completed_at DATETIME(6) NOT NULL, PRIMARY KEY(member_id, scene_id, mission_run_id), UNIQUE KEY uk_object_key(object_key))"))
                .then(execute("CREATE TABLE picture (id BIGINT AUTO_INCREMENT PRIMARY KEY, created_at DATETIME(6), image VARCHAR(255) NOT NULL, progress_id BIGINT NOT NULL)"))
                .then(execute("INSERT INTO progress(member_id, scene_id, played_at) VALUES (15, 2, '2026-01-01 00:00:00.000000')"))
                .block();
    }

    @Test
    void pictureFailureRollsBackClaimProgressAndPicture() {
        String missionRunId = UUID.randomUUID().toString();
        String failingObjectKey = "x".repeat(300);

        assertThrows(Throwable.class, () -> service.saveCompletionIfFirst(
                failingObjectKey, 2, 15, missionRunId).block());

        assertEquals(0L, count("SELECT COUNT(*) FROM mission_completion"));
        assertEquals(0L, count("SELECT COUNT(*) FROM picture"));
        assertEquals(0L, count("SELECT COUNT(*) FROM progress WHERE played_at <> '2026-01-01 00:00:00.000000'"));
    }

    @Test
    void successfulCompletionAndDuplicateAreIdempotent() {
        String missionRunId = UUID.randomUUID().toString();
        assertEquals(Boolean.TRUE, service.saveCompletionIfFirst("picture/ok.jpg", 2, 15, missionRunId).block());
        assertEquals(Boolean.FALSE, service.saveCompletionIfFirst("picture/duplicate.jpg", 2, 15, missionRunId).block());
        assertEquals(1L, count("SELECT COUNT(*) FROM mission_completion"));
        assertEquals(1L, count("SELECT COUNT(*) FROM picture"));
        assertEquals(1L, count("SELECT COUNT(*) FROM progress WHERE played_at <> '2026-01-01 00:00:00.000000'"));
    }

    private Mono<Void> execute(String sql) {
        return databaseClient.sql(sql).then();
    }

    private long count(String sql) {
        return databaseClient.sql(sql).map((row, metadata) -> row.get(0, Long.class)).one().block();
    }
}
