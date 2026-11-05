-- ============================================================================
--  055 · Multi-Yard Data Sync, Soft Deletes, and Auto-Tracking Triggers
--
--  Prepares the database for distributed multi-yard operation (e.g. GL1, GL2, etc.)
--  allowing seamless synchronization into a Centralized Server without primary key
--  or data integrity conflicts.
--
--  Includes:
--    1. UUID extensions (uuid-ossp, pgcrypto).
--    2. Trigger function `fn_set_sync_metadata` for `updated_at`, `sync_version`,
--       and protection against accidental modification of origin `yard_id`.
--    3. Helper function `fn_enable_multi_yard_sync` to ensure sync columns and
--       indexes exist across tables.
--    4. Iterative configuration across all base business tables with default 'GL1'.
--    5. Schema migration version bump to 55 in `public.schema_migrations`.
-- ============================================================================

set client_min_messages = warning;

-- 1. Ensure UUID and Crypto extensions are enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Trigger Function: Automatically manage updated_at and increment sync_version
CREATE OR REPLACE FUNCTION public.fn_set_sync_metadata()
RETURNS TRIGGER AS $$
BEGIN
    -- Record timestamp of change in UTC
    NEW.updated_at = clock_timestamp();

    -- Increment sync version for conflict detection and delta synchronization
    NEW.sync_version = COALESCE(OLD.sync_version, 0) + 1;

    -- Safeguard origin yard_id from accidental mutation once set
    IF OLD.yard_id IS NOT NULL AND NEW.yard_id IS DISTINCT FROM OLD.yard_id THEN
        RAISE EXCEPTION 'yard_id cannot be modified once set (Origin yard protection).';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Dynamic Helper Function: Add columns, indexes, and triggers to a given table
CREATE OR REPLACE FUNCTION public.fn_enable_multi_yard_sync(target_table TEXT, default_yard TEXT DEFAULT 'GL1')
RETURNS VOID AS $$
DECLARE
    idx_yard_name TEXT;
    idx_sync_name TEXT;
    trg_name TEXT;
BEGIN
    idx_yard_name := 'idx_' || target_table || '_yard_id';
    idx_sync_name := 'idx_' || target_table || '_sync_track';
    trg_name      := 'trg_sync_metadata_' || target_table;

    -- Add yard_id (with DEFAULT)
    EXECUTE format('
        ALTER TABLE public.%I 
        ADD COLUMN IF NOT EXISTS yard_id VARCHAR(20) DEFAULT %L;
    ', target_table, default_yard);

    -- If the table had an existing `yard` column, copy values to `yard_id` where null
    -- Note: on audit_logs, UPDATE is blocked by trigger, so handle with trigger bypass if needed
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = target_table 
          AND column_name = 'yard'
    ) THEN
        IF target_table = 'audit_logs' THEN
            -- audit_logs is append-only, disable trigger temporarily for backfill if needed
            BEGIN
                ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_no_update;
                UPDATE public.audit_logs 
                SET yard_id = COALESCE(yard, default_yard) 
                WHERE yard_id IS NULL OR yard_id = default_yard;
                ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_no_update;
            EXCEPTION WHEN OTHERS THEN
                ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_no_update;
                RAISE;
            END;
        ELSE
            EXECUTE format('
                UPDATE public.%I 
                SET yard_id = COALESCE(yard, %L) 
                WHERE yard_id IS NULL;
            ', target_table, default_yard);
        END IF;
    ELSE
        IF target_table = 'audit_logs' THEN
            BEGIN
                ALTER TABLE public.audit_logs DISABLE TRIGGER audit_logs_no_update;
                UPDATE public.audit_logs SET yard_id = default_yard WHERE yard_id IS NULL;
                ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_no_update;
            EXCEPTION WHEN OTHERS THEN
                ALTER TABLE public.audit_logs ENABLE TRIGGER audit_logs_no_update;
                RAISE;
            END;
        ELSE
            EXECUTE format('
                UPDATE public.%I 
                SET yard_id = %L 
                WHERE yard_id IS NULL;
            ', target_table, default_yard);
        END IF;
    END IF;

    -- Make yard_id NOT NULL after backfill
    EXECUTE format('
        ALTER TABLE public.%I 
        ALTER COLUMN yard_id SET NOT NULL;
    ', target_table);

    -- created_at column
    EXECUTE format('
        ALTER TABLE public.%I 
        ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp();
    ', target_table);

    -- updated_at column
    EXECUTE format('
        ALTER TABLE public.%I 
        ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp();
    ', target_table);

    -- is_deleted (Soft Delete) column
    EXECUTE format('
        ALTER TABLE public.%I 
        ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;
    ', target_table);

    -- sync_version column
    EXECUTE format('
        ALTER TABLE public.%I 
        ADD COLUMN IF NOT EXISTS sync_version BIGINT NOT NULL DEFAULT 1;
    ', target_table);

    -- Indexes for efficient yard scoping and delta sync queries
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON public.%I (yard_id);
    ', idx_yard_name, target_table);

    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON public.%I (updated_at, sync_version);
    ', idx_sync_name, target_table);

    -- Attach BEFORE UPDATE trigger (skip on append-only audit_logs which forbids updates)
    IF target_table <> 'audit_logs' THEN
        EXECUTE format('
            DROP TRIGGER IF EXISTS %I ON public.%I;
            CREATE TRIGGER %I
            BEFORE UPDATE ON public.%I
            FOR EACH ROW
            EXECUTE FUNCTION public.fn_set_sync_metadata();
        ', trg_name, target_table, trg_name, target_table);
    END IF;

END;
$$ LANGUAGE plpgsql;

-- 4. Apply multi-yard sync metadata across all public user/business base tables
DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN 
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
          AND table_type = 'BASE TABLE'
          -- Exclude migration tracking and system/log-only tables that do not sync
          AND table_name NOT IN (
              'schema_migrations', 
              '_prisma_migrations', 
              'refused_sign_in_pending'
          )
    LOOP
        PERFORM public.fn_enable_multi_yard_sync(tbl.table_name, 'GL1');
    END LOOP;
END;
$$;

-- 5. Record Migration in public.schema_migrations
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations') THEN
        INSERT INTO public.schema_migrations (version, name)
        VALUES (55, '055_multi_yard_sync')
        ON CONFLICT (version) DO UPDATE SET name = EXCLUDED.name, applied_at = now();
    END IF;
END $$;
