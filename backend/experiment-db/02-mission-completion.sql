CREATE TABLE IF NOT EXISTS mission_completion (
  member_id BIGINT NOT NULL,
  scene_id BIGINT NOT NULL,
  mission_run_id VARCHAR(191) NOT NULL,
  object_key VARCHAR(255) NOT NULL,
  completed_at DATETIME(6) NOT NULL,
  PRIMARY KEY (member_id, scene_id, mission_run_id),
  UNIQUE KEY uk_mission_completion_object_key (object_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
