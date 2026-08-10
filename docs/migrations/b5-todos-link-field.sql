-- B5: Add meeting_url (generic link) column to todos
-- Run this in the Supabase SQL Editor.
-- All statements are idempotent (IF NOT EXISTS / DO $$ guards).

-- 1. Add meeting_url column (stores any URL -- Zoom, Meet, Docs, Figma, Notion, etc.)
ALTER TABLE todos
    ADD COLUMN IF NOT EXISTS meeting_url text;

-- 2. Ensure color values are constrained to the iOS palette
--    (If the constraint already exists this block is a no-op.)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'todos' AND constraint_name = 'todos_color_check'
    ) THEN
        ALTER TABLE todos
            ADD CONSTRAINT todos_color_check
            CHECK (color IS NULL OR color IN ('coral','amber','sage','sky','indigo','violet'));
    END IF;
END $$;

-- 3. Verify (optional, remove before production):
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'todos'
--   AND column_name IN ('color','emoji','estimated_minutes','meeting_url')
-- ORDER BY column_name;
