-- ============================================================
-- Supabase RLS Policy Update for ROI CRM
-- Run this in the Supabase SQL Editor AFTER creating auth users
-- and AFTER verifying that Supabase Auth login works.
-- ============================================================

-- ============================================================
-- 1. UPDATE HELPER FUNCTIONS to use Supabase Auth JWT claims
-- ============================================================

-- Extract username from the authenticated user's JWT metadata
CREATE OR REPLACE FUNCTION current_username()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    auth.jwt() -> 'user_metadata' ->> 'username',
    'anonymous'
  );
$$;

-- Extract role from the authenticated user's JWT metadata
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    auth.jwt() -> 'user_metadata' ->> 'role',
    'agent'
  );
$$;

-- ============================================================
-- 2. DROP ALL TEMPORARY ANON POLICIES
-- ============================================================
-- These were created to allow unauthenticated access during development.
-- Now that auth is working, we remove them.

-- Helper: drop policies safely (ignores if they don't exist)
DO $$
DECLARE
  _table TEXT;
  _policy TEXT;
BEGIN
  -- Find and drop all policies starting with 'temp_anon'
  FOR _table, _policy IN
    SELECT schemaname || '.' || tablename, policyname
    FROM pg_policies
    WHERE policyname LIKE 'temp_anon%'
      AND schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %s', _policy, _table);
    RAISE NOTICE 'Dropped policy: % on %', _policy, _table;
  END LOOP;
END $$;

-- ============================================================
-- 3. ENSURE AUTHENTICATED RLS POLICIES EXIST
-- ============================================================
-- These policies restrict access to authenticated users only.
-- They use the helper functions above to check username/role from JWT.

-- List of all CRM tables that need RLS
-- leads, deals, clients, payments, products, meetings, tasks,
-- notes, record_tasks, record_history, files

-- Enable RLS on all tables (idempotent)
DO $$
DECLARE
  _table TEXT;
BEGIN
  FOR _table IN
    SELECT unnest(ARRAY[
      'leads', 'deals', 'clients', 'payments', 'products',
      'meetings', 'tasks', 'notes', 'record_tasks', 'record_history', 'files'
    ])
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', _table);
  END LOOP;
END $$;

-- Create authenticated SELECT policies (all authenticated users can read all records)
DO $$
DECLARE
  _table TEXT;
BEGIN
  FOR _table IN
    SELECT unnest(ARRAY[
      'leads', 'deals', 'clients', 'payments', 'products',
      'meetings', 'tasks', 'notes', 'record_tasks', 'record_history', 'files'
    ])
  LOOP
    -- Drop existing policy if it exists, then recreate
    EXECUTE format('DROP POLICY IF EXISTS "auth_select_%1$s" ON public.%1$I', _table);
    EXECUTE format(
      'CREATE POLICY "auth_select_%1$s" ON public.%1$I FOR SELECT TO authenticated USING (true)',
      _table
    );
  END LOOP;
END $$;

-- Create authenticated INSERT policies (all authenticated users can insert)
DO $$
DECLARE
  _table TEXT;
BEGIN
  FOR _table IN
    SELECT unnest(ARRAY[
      'leads', 'deals', 'clients', 'payments', 'products',
      'meetings', 'tasks', 'notes', 'record_tasks', 'record_history', 'files'
    ])
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "auth_insert_%1$s" ON public.%1$I', _table);
    EXECUTE format(
      'CREATE POLICY "auth_insert_%1$s" ON public.%1$I FOR INSERT TO authenticated WITH CHECK (true)',
      _table
    );
  END LOOP;
END $$;

-- Create authenticated UPDATE policies (all authenticated users can update)
DO $$
DECLARE
  _table TEXT;
BEGIN
  FOR _table IN
    SELECT unnest(ARRAY[
      'leads', 'deals', 'clients', 'payments', 'products',
      'meetings', 'tasks', 'notes', 'record_tasks', 'record_history', 'files'
    ])
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "auth_update_%1$s" ON public.%1$I', _table);
    EXECUTE format(
      'CREATE POLICY "auth_update_%1$s" ON public.%1$I FOR UPDATE TO authenticated USING (true) WITH CHECK (true)',
      _table
    );
  END LOOP;
END $$;

-- Create authenticated DELETE policies (only admin role can delete)
DO $$
DECLARE
  _table TEXT;
BEGIN
  FOR _table IN
    SELECT unnest(ARRAY[
      'leads', 'deals', 'clients', 'payments', 'products',
      'meetings', 'tasks', 'notes', 'record_tasks', 'record_history', 'files'
    ])
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS "auth_delete_%1$s" ON public.%1$I', _table);
    EXECUTE format(
      'CREATE POLICY "auth_delete_%1$s" ON public.%1$I FOR DELETE TO authenticated USING (current_user_role() = ''admin'' AND current_username() = ''roi'')',
      _table
    );
  END LOOP;
END $$;

-- ============================================================
-- 4. VERIFY
-- ============================================================
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd;
