-- ============================================================
-- Workout Schema  |  2026-08-11
-- 분리 테이블 설계:
--   workout_logs        → HealthKit 원본 수치 (사실 데이터, append-only)
--   workout_log_details → 사용자 편집 영역 (자주 바뀌는 항목)
--   workout_log_full    → 조인 읽기 뷰 (Edge Function GET 전용)
-- ============================================================

-- ── 1. 핵심 사실 데이터 (불변 / HealthKit 소스) ───────────────
CREATE TABLE IF NOT EXISTS workout_logs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    hk_uuid         TEXT,                             -- HealthKit UUID (수동 입력이면 NULL)
    source          TEXT        NOT NULL DEFAULT 'manual', -- 'healthkit' | 'manual'
    activity_type   TEXT        NOT NULL,             -- 'running' | 'cycling' | 'strength_training' | …
    started_at      TIMESTAMPTZ NOT NULL,
    ended_at        TIMESTAMPTZ NOT NULL,
    duration_sec    INT         NOT NULL,
    distance_m      DOUBLE PRECISION,                 -- 유산소 운동만
    calories        DOUBLE PRECISION,
    avg_heart_rate  DOUBLE PRECISION,
    route_image_url TEXT,                             -- GPS 경로 자동 렌더 (비동기 업로드)
    photo_url       TEXT,                             -- 사용자 첨부 사진 (Nike RC 캡처 등)
    scheduled_date  DATE        NOT NULL,             -- 캘린더 배치 기준
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 2. 사용자 편집 영역 (자주 바뀌는 항목 분리) ───────────────
CREATE TABLE IF NOT EXISTS workout_log_details (
    workout_log_id  UUID        PRIMARY KEY REFERENCES workout_logs(id) ON DELETE CASCADE,
    location_name   TEXT,                             -- "강남 헬스장" (직접 입력)
    notes           TEXT        NOT NULL DEFAULT '',
    exercises       JSONB,
    -- [{name, sets, reps, weight_kg, duration_sec}]
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 3. 읽기 전용 조인 뷰 (Edge Function SELECT 전용) ──────────
CREATE OR REPLACE VIEW workout_log_full AS
SELECT
    wl.id,
    wl.user_id,
    wl.hk_uuid,
    wl.source,
    wl.activity_type,
    wl.started_at,
    wl.ended_at,
    wl.duration_sec,
    wl.distance_m,
    wl.calories,
    wl.avg_heart_rate,
    wl.route_image_url,
    wl.photo_url,
    wl.scheduled_date,
    wl.created_at,
    COALESCE(wd.location_name, '') AS location_name,
    COALESCE(wd.notes, '')         AS notes,
    wd.exercises,
    wd.updated_at                  AS detail_updated_at
FROM workout_logs wl
LEFT JOIN workout_log_details wd ON wl.id = wd.workout_log_id;

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE workout_logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_log_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_workouts"
    ON workout_logs FOR ALL
    USING  (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users_own_details"
    ON workout_log_details FOR ALL
    USING (
        EXISTS (SELECT 1 FROM workout_logs
                WHERE id = workout_log_id AND user_id = auth.uid())
    )
    WITH CHECK (
        EXISTS (SELECT 1 FROM workout_logs
                WHERE id = workout_log_id AND user_id = auth.uid())
    );

-- ── Indexes — workout_logs ────────────────────────────────────

-- 캘린더 날짜 범위 조회 (가장 빈번한 쿼리)
CREATE INDEX IF NOT EXISTS idx_wl_user_date
    ON workout_logs (user_id, scheduled_date DESC);

-- HealthKit dedup: 재가져오기 방지
CREATE UNIQUE INDEX IF NOT EXISTS idx_wl_hk_uuid
    ON workout_logs (hk_uuid)
    WHERE hk_uuid IS NOT NULL;

-- Today 탭: 최신 운동 우선
CREATE INDEX IF NOT EXISTS idx_wl_user_started
    ON workout_logs (user_id, started_at DESC);

-- Partial: HealthKit 소스만 (dedup 쿼리 집중 최적화)
CREATE INDEX IF NOT EXISTS idx_wl_hk_source
    ON workout_logs (user_id, hk_uuid)
    WHERE source = 'healthkit' AND hk_uuid IS NOT NULL;

-- ── Indexes — todos (기존 테이블 최적화 추가) ─────────────────

-- 캘린더 날짜 범위 조회
CREATE INDEX IF NOT EXISTS idx_todos_user_date
    ON todos (user_id, scheduled_date DESC);

-- 활성 할 일만 (완료/취소 제외) — Today 탭 핵심 쿼리
CREATE INDEX IF NOT EXISTS idx_todos_user_active
    ON todos (user_id, scheduled_date)
    WHERE status NOT IN ('completed', 'cancelled', 'skipped');

-- 반복 규칙 조회
CREATE INDEX IF NOT EXISTS idx_todos_rule
    ON todos (schedule_rule_id)
    WHERE schedule_rule_id IS NOT NULL;

-- ── Supabase Storage (대시보드에서 수동 생성) ─────────────────
-- Bucket 이름: workout-media
-- 접근 방식: Private (서명 URL 사용)
-- 허용 MIME: image/jpeg, image/png
-- 최대 파일 크기: 5MB
-- Path 구조: {workout_id}/route.jpg  (GPS 자동)
--            {workout_id}/photo.jpg  (사용자 첨부)
