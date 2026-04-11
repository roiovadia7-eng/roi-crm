-- ============================================================
-- ROI CRM — Supabase Schema Migration
-- Run this entire file in the Supabase SQL Editor
-- ============================================================

-- ============================================================
-- 0. EXTENSIONS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. HELPER FUNCTIONS (JWT claim extraction)
-- ============================================================
CREATE OR REPLACE FUNCTION public.current_username()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    current_setting('request.jwt.claims', true)::json ->> 'username',
    current_setting('request.jwt.claims', true)::json -> 'app_metadata' ->> 'username'
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    current_setting('request.jwt.claims', true)::json ->> 'user_role',
    current_setting('request.jwt.claims', true)::json -> 'app_metadata' ->> 'user_role'
  );
$$;

-- ============================================================
-- 2. USERS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT,
  display_name  TEXT NOT NULL,
  role          TEXT NOT NULL DEFAULT 'agent' CHECK (role IN ('admin', 'agent')),
  phone         TEXT,
  email         TEXT,
  id_number     TEXT,
  avatar        TEXT,
  color         TEXT,
  role_label    TEXT,
  failed_login_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 3. CRM DATA TABLES
-- ============================================================

-- ---------- LEADS ----------
CREATE TABLE IF NOT EXISTS public.leads (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  phone           TEXT,
  email           TEXT,
  status          TEXT,
  agent           TEXT,
  source          TEXT,
  why_contact     TEXT,                -- whyContact
  is_gold         BOOLEAN DEFAULT FALSE, -- isGold
  whatsapp_link   TEXT,                -- whatsappLink
  relevant_date   DATE,                -- relevantDate
  course          TEXT,
  created_by      TEXT,
  updated_by      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- DEALS ----------
CREATE TABLE IF NOT EXISTS public.deals (
  id                      TEXT PRIMARY KEY,
  name                    TEXT NOT NULL,
  lead_id                 TEXT REFERENCES public.leads(id) ON DELETE SET NULL,
  lead_name               TEXT,
  executor                TEXT,
  status                  TEXT,
  product_id              TEXT,           -- FK added after products table
  product_name            TEXT,
  payment_type            TEXT,
  num_payments            INTEGER,
  deal_total              NUMERIC(12,2),
  total_collected         NUMERIC(12,2) DEFAULT 0,
  remaining_balance       NUMERIC(12,2) DEFAULT 0,
  credit_details          TEXT,
  contract_link           TEXT,
  credit_frame_link       TEXT,
  standing_order_link     TEXT,
  future_collection_date  DATE,
  invoice_issued          BOOLEAN DEFAULT FALSE,
  created_by              TEXT,
  updated_by              TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- PRODUCTS ----------
CREATE TABLE IF NOT EXISTS public.products (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  price       NUMERIC(12,2),
  description TEXT,                     -- "desc" in app
  created_by  TEXT,
  updated_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FK: deals.product_id → products.id
ALTER TABLE public.deals
  ADD CONSTRAINT deals_product_id_fk
  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL;

-- ---------- CLIENTS ----------
CREATE TABLE IF NOT EXISTS public.clients (
  id                      TEXT PRIMARY KEY,
  name                    TEXT NOT NULL,
  client_phone            TEXT,
  client_email            TEXT,
  advisor                 TEXT,
  advisor_name            TEXT,
  advisor_email           TEXT,
  advisor_phone           TEXT,
  client_status           TEXT,
  start_date              DATE,
  end_date                DATE,
  done_meetings           INTEGER DEFAULT 0,
  total_meetings          INTEGER,
  deal_id                 TEXT REFERENCES public.deals(id) ON DELETE SET NULL,
  deal_name               TEXT,
  deal_ref                TEXT,
  lead_id                 TEXT REFERENCES public.leads(id) ON DELETE SET NULL,
  lead_name               TEXT,
  avg_months_in_process   NUMERIC(6,1),
  days_in_process         INTEGER,
  created_by              TEXT,
  updated_by              TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- PAYMENTS ----------
CREATE TABLE IF NOT EXISTS public.payments (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  deal_id         TEXT REFERENCES public.deals(id) ON DELETE SET NULL,
  deal_name       TEXT,
  payment_type    TEXT,
  amount          NUMERIC(12,2),
  num_payments    INTEGER,
  payment_number  INTEGER,             -- paymentNumber in app
  setup_date      DATE,
  payment_date    DATE,                -- "date money in bank"
  status          TEXT,
  invoice_issued  BOOLEAN DEFAULT FALSE,
  executor        TEXT,
  product_id      TEXT REFERENCES public.products(id) ON DELETE SET NULL,
  created_by      TEXT,
  updated_by      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- MEETINGS ----------
CREATE TABLE IF NOT EXISTS public.meetings (
  id              TEXT PRIMARY KEY,
  title           TEXT NOT NULL,
  name            TEXT,                -- alias for title in some contexts
  client_name     TEXT,
  client_id       TEXT REFERENCES public.clients(id) ON DELETE SET NULL,
  agent           TEXT,
  meeting_number  INTEGER,
  start_date      DATE,
  end_date        DATE,
  start_time      TEXT,
  end_time        TEXT,
  status          TEXT,
  roi_email       TEXT,
  notes_field     TEXT,                -- meeting description/notes
  lead_id         TEXT REFERENCES public.leads(id) ON DELETE SET NULL,
  deal_id         TEXT REFERENCES public.deals(id) ON DELETE SET NULL,
  created_by      TEXT,
  updated_by      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- TASKS ----------
CREATE TABLE IF NOT EXISTS public.tasks (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  description     TEXT,
  executor        TEXT,
  due_date        DATE,
  due_time        TEXT,                -- HH:MM for reminder pop-up
  reminder_date   DATE,
  lead_ref        TEXT,                -- display name of related record
  related_id      TEXT,                -- generic FK to any parent record
  related_name    TEXT,
  related_type    TEXT,                -- e.g. 'leads', 'deals', 'clients'
  done            BOOLEAN DEFAULT FALSE,
  task_type       TEXT,
  priority        TEXT,
  created_by      TEXT,
  updated_by      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 4. NOTES TABLE (denormalized from embedded arrays)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.notes (
  id            TEXT PRIMARY KEY DEFAULT 'n' || substr(md5(random()::text), 1, 12),
  record_type   TEXT NOT NULL,         -- 'leads', 'deals', etc.
  record_id     TEXT NOT NULL,
  text          TEXT,
  author        TEXT,
  note_type     TEXT NOT NULL DEFAULT 'note' CHECK (note_type IN ('note', 'call_log')),
  call_summary  TEXT,
  call_result   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 5. RECORD TASKS TABLE (denormalized from embedded arrays)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.record_tasks (
  id            TEXT PRIMARY KEY DEFAULT 'rt' || substr(md5(random()::text), 1, 12),
  record_type   TEXT NOT NULL,
  record_id     TEXT NOT NULL,
  name          TEXT NOT NULL,
  executor      TEXT,
  due_date      DATE,
  reminder_date DATE,
  done          BOOLEAN DEFAULT FALSE,
  created_by    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 6. FILES / ATTACHMENTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.files (
  id            TEXT PRIMARY KEY DEFAULT 'f' || substr(md5(random()::text), 1, 12),
  record_type   TEXT NOT NULL,
  record_id     TEXT NOT NULL,
  file_name     TEXT NOT NULL,
  file_url      TEXT NOT NULL,
  uploaded_by   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 7. AUDIT LOG TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.audit_log (
  id            BIGSERIAL PRIMARY KEY,
  table_name    TEXT NOT NULL,
  record_id     TEXT NOT NULL,
  field_name    TEXT,
  old_value     TEXT,
  new_value     TEXT,
  action        TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
  performed_by  TEXT,
  performed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 8. USER PREFERENCES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_preferences (
  id            TEXT PRIMARY KEY DEFAULT 'up' || substr(md5(random()::text), 1, 12),
  username      TEXT NOT NULL,
  pref_key      TEXT NOT NULL,
  pref_value    JSONB,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (username, pref_key)
);

-- ============================================================
-- 9. LOGIN ATTEMPTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.login_attempts (
  id            TEXT PRIMARY KEY DEFAULT 'la' || substr(md5(random()::text), 1, 12),
  username      TEXT NOT NULL,
  ip_address    INET,
  success       BOOLEAN NOT NULL DEFAULT FALSE,
  attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 10. OTP CODES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.otp_codes (
  id            TEXT PRIMARY KEY DEFAULT 'otp' || substr(md5(random()::text), 1, 12),
  username      TEXT NOT NULL,
  code          TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL,
  used          BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 11. HISTORY TABLE (field-level change history per record)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.record_history (
  id            TEXT PRIMARY KEY DEFAULT 'h' || substr(md5(random()::text), 1, 12),
  record_type   TEXT NOT NULL,
  record_id     TEXT NOT NULL,
  field         TEXT NOT NULL,
  old_val       TEXT,
  new_val       TEXT,
  changed_by    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 12. INDEXES
-- ============================================================

-- Leads
CREATE INDEX IF NOT EXISTS idx_leads_agent        ON public.leads(agent);
CREATE INDEX IF NOT EXISTS idx_leads_status       ON public.leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_created_by   ON public.leads(created_by);
CREATE INDEX IF NOT EXISTS idx_leads_created_at   ON public.leads(created_at);

-- Deals
CREATE INDEX IF NOT EXISTS idx_deals_lead_id      ON public.deals(lead_id);
CREATE INDEX IF NOT EXISTS idx_deals_executor      ON public.deals(executor);
CREATE INDEX IF NOT EXISTS idx_deals_status        ON public.deals(status);
CREATE INDEX IF NOT EXISTS idx_deals_product_id    ON public.deals(product_id);
CREATE INDEX IF NOT EXISTS idx_deals_created_by    ON public.deals(created_by);
CREATE INDEX IF NOT EXISTS idx_deals_created_at    ON public.deals(created_at);

-- Clients
CREATE INDEX IF NOT EXISTS idx_clients_deal_id     ON public.clients(deal_id);
CREATE INDEX IF NOT EXISTS idx_clients_lead_id     ON public.clients(lead_id);
CREATE INDEX IF NOT EXISTS idx_clients_advisor     ON public.clients(advisor);
CREATE INDEX IF NOT EXISTS idx_clients_status      ON public.clients(client_status);
CREATE INDEX IF NOT EXISTS idx_clients_created_by  ON public.clients(created_by);

-- Payments
CREATE INDEX IF NOT EXISTS idx_payments_deal_id      ON public.payments(deal_id);
CREATE INDEX IF NOT EXISTS idx_payments_executor      ON public.payments(executor);
CREATE INDEX IF NOT EXISTS idx_payments_status        ON public.payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_setup_date    ON public.payments(setup_date);
CREATE INDEX IF NOT EXISTS idx_payments_payment_date  ON public.payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_payments_product_id    ON public.payments(product_id);
CREATE INDEX IF NOT EXISTS idx_payments_created_by    ON public.payments(created_by);

-- Products
CREATE INDEX IF NOT EXISTS idx_products_created_by ON public.products(created_by);

-- Meetings
CREATE INDEX IF NOT EXISTS idx_meetings_client_id  ON public.meetings(client_id);
CREATE INDEX IF NOT EXISTS idx_meetings_lead_id    ON public.meetings(lead_id);
CREATE INDEX IF NOT EXISTS idx_meetings_deal_id    ON public.meetings(deal_id);
CREATE INDEX IF NOT EXISTS idx_meetings_agent      ON public.meetings(agent);
CREATE INDEX IF NOT EXISTS idx_meetings_start_date ON public.meetings(start_date);
CREATE INDEX IF NOT EXISTS idx_meetings_created_by ON public.meetings(created_by);

-- Tasks
CREATE INDEX IF NOT EXISTS idx_tasks_executor      ON public.tasks(executor);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date      ON public.tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_related_id    ON public.tasks(related_id);
CREATE INDEX IF NOT EXISTS idx_tasks_done          ON public.tasks(done);
CREATE INDEX IF NOT EXISTS idx_tasks_created_by    ON public.tasks(created_by);

-- Notes
CREATE INDEX IF NOT EXISTS idx_notes_record        ON public.notes(record_type, record_id);
CREATE INDEX IF NOT EXISTS idx_notes_author        ON public.notes(author);

-- Record Tasks
CREATE INDEX IF NOT EXISTS idx_record_tasks_record ON public.record_tasks(record_type, record_id);
CREATE INDEX IF NOT EXISTS idx_record_tasks_executor ON public.record_tasks(executor);

-- Files
CREATE INDEX IF NOT EXISTS idx_files_record        ON public.files(record_type, record_id);

-- Audit Log
CREATE INDEX IF NOT EXISTS idx_audit_log_table_record ON public.audit_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_performed_at ON public.audit_log(performed_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_performed_by ON public.audit_log(performed_by);

-- User Preferences
CREATE INDEX IF NOT EXISTS idx_user_prefs_username ON public.user_preferences(username);

-- Login Attempts
CREATE INDEX IF NOT EXISTS idx_login_attempts_username ON public.login_attempts(username);
CREATE INDEX IF NOT EXISTS idx_login_attempts_at       ON public.login_attempts(attempted_at);

-- OTP Codes
CREATE INDEX IF NOT EXISTS idx_otp_codes_username  ON public.otp_codes(username);
CREATE INDEX IF NOT EXISTS idx_otp_codes_expires   ON public.otp_codes(expires_at);

-- Record History
CREATE INDEX IF NOT EXISTS idx_record_history_record ON public.record_history(record_type, record_id);
CREATE INDEX IF NOT EXISTS idx_record_history_at     ON public.record_history(created_at);

-- ============================================================
-- 13. AUDIT TRIGGER FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION public.audit_trigger_func()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  _username TEXT;
  _col      TEXT;
  _old_val  TEXT;
  _new_val  TEXT;
BEGIN
  _username := coalesce(public.current_username(), 'system');

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.audit_log (table_name, record_id, action, performed_by)
    VALUES (TG_TABLE_NAME, NEW.id::TEXT, 'INSERT', _username);
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.audit_log (table_name, record_id, action, performed_by)
    VALUES (TG_TABLE_NAME, OLD.id::TEXT, 'DELETE', _username);
    RETURN OLD;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Log each changed column individually
    FOR _col IN
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = TG_TABLE_SCHEMA
        AND table_name   = TG_TABLE_NAME
        AND column_name NOT IN ('created_at', 'updated_at', 'updated_by')
    LOOP
      EXECUTE format('SELECT ($1).%I::TEXT', _col) INTO _old_val USING OLD;
      EXECUTE format('SELECT ($1).%I::TEXT', _col) INTO _new_val USING NEW;

      IF _old_val IS DISTINCT FROM _new_val THEN
        INSERT INTO public.audit_log (table_name, record_id, field_name, old_value, new_value, action, performed_by)
        VALUES (TG_TABLE_NAME, NEW.id::TEXT, _col, _old_val, _new_val, 'UPDATE', _username);
      END IF;
    END LOOP;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

-- Apply audit triggers to all data tables
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'leads', 'deals', 'clients', 'payments', 'products',
    'meetings', 'tasks', 'notes', 'record_tasks', 'files'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS audit_%I ON public.%I', t, t
    );
    EXECUTE format(
      'CREATE TRIGGER audit_%I AFTER INSERT OR UPDATE OR DELETE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.audit_trigger_func()',
      t, t
    );
  END LOOP;
END;
$$;

-- ============================================================
-- 14. AUTO-UPDATE updated_at TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users', 'leads', 'deals', 'clients', 'payments',
    'products', 'meetings', 'tasks'
  ] LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS set_updated_at_%I ON public.%I', t, t
    );
    EXECUTE format(
      'CREATE TRIGGER set_updated_at_%I BEFORE UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()',
      t, t
    );
  END LOOP;
END;
$$;

-- ============================================================
-- 15. ROW LEVEL SECURITY (RLS)
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE public.users            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deals            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meetings         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.record_tasks     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.files            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_attempts   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_codes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.record_history   ENABLE ROW LEVEL SECURITY;

-- -------------------- USERS --------------------
CREATE POLICY users_admin_all ON public.users
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY users_agent_read_self ON public.users
  FOR SELECT USING (username = public.current_username());

-- -------------------- LEADS --------------------
CREATE POLICY leads_admin_all ON public.leads
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY leads_agent_select ON public.leads
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (agent = public.current_username() OR created_by = public.current_username())
  );

CREATE POLICY leads_agent_insert ON public.leads
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY leads_agent_update ON public.leads
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (agent = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- DEALS --------------------
CREATE POLICY deals_admin_all ON public.deals
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY deals_agent_select ON public.deals
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

CREATE POLICY deals_agent_insert ON public.deals
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY deals_agent_update ON public.deals
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- CLIENTS --------------------
CREATE POLICY clients_admin_all ON public.clients
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY clients_agent_select ON public.clients
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (advisor = public.current_username() OR created_by = public.current_username())
  );

CREATE POLICY clients_agent_insert ON public.clients
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY clients_agent_update ON public.clients
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (advisor = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- PAYMENTS --------------------
CREATE POLICY payments_admin_all ON public.payments
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY payments_agent_select ON public.payments
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

CREATE POLICY payments_agent_insert ON public.payments
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY payments_agent_update ON public.payments
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- PRODUCTS --------------------
CREATE POLICY products_admin_all ON public.products
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY products_authenticated_read ON public.products
  FOR SELECT USING (public.current_username() IS NOT NULL);

-- -------------------- MEETINGS --------------------
CREATE POLICY meetings_admin_all ON public.meetings
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY meetings_agent_select ON public.meetings
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (agent = public.current_username() OR created_by = public.current_username())
  );

CREATE POLICY meetings_agent_insert ON public.meetings
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY meetings_agent_update ON public.meetings
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (agent = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- TASKS --------------------
CREATE POLICY tasks_admin_all ON public.tasks
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY tasks_agent_select ON public.tasks
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

CREATE POLICY tasks_agent_insert ON public.tasks
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY tasks_agent_update ON public.tasks
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- NOTES (inherit from parent record) --------------------
CREATE POLICY notes_admin_all ON public.notes
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY notes_agent_select ON public.notes
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (
      author = public.current_username()
      OR EXISTS (
        SELECT 1 FROM public.leads   WHERE leads.id   = notes.record_id AND (leads.agent = public.current_username() OR leads.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.deals   WHERE deals.id   = notes.record_id AND (deals.executor = public.current_username() OR deals.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.clients WHERE clients.id = notes.record_id AND (clients.advisor = public.current_username() OR clients.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.tasks   WHERE tasks.id   = notes.record_id AND (tasks.executor = public.current_username() OR tasks.created_by = public.current_username())
      )
    )
  );

CREATE POLICY notes_agent_insert ON public.notes
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY notes_agent_delete ON public.notes
  FOR DELETE USING (
    public.current_user_role() = 'agent'
    AND author = public.current_username()
  );

-- -------------------- RECORD TASKS (inherit from parent) --------------------
CREATE POLICY record_tasks_admin_all ON public.record_tasks
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY record_tasks_agent_select ON public.record_tasks
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (
      executor = public.current_username()
      OR created_by = public.current_username()
      OR EXISTS (
        SELECT 1 FROM public.leads   WHERE leads.id   = record_tasks.record_id AND (leads.agent = public.current_username() OR leads.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.deals   WHERE deals.id   = record_tasks.record_id AND (deals.executor = public.current_username() OR deals.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.clients WHERE clients.id = record_tasks.record_id AND (clients.advisor = public.current_username() OR clients.created_by = public.current_username())
      )
    )
  );

CREATE POLICY record_tasks_agent_insert ON public.record_tasks
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

CREATE POLICY record_tasks_agent_update ON public.record_tasks
  FOR UPDATE USING (
    public.current_user_role() = 'agent'
    AND (executor = public.current_username() OR created_by = public.current_username())
  );

-- -------------------- FILES --------------------
CREATE POLICY files_admin_all ON public.files
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY files_agent_select ON public.files
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (
      uploaded_by = public.current_username()
      OR EXISTS (
        SELECT 1 FROM public.leads   WHERE leads.id   = files.record_id AND (leads.agent = public.current_username() OR leads.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.deals   WHERE deals.id   = files.record_id AND (deals.executor = public.current_username() OR deals.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.clients WHERE clients.id = files.record_id AND (clients.advisor = public.current_username() OR clients.created_by = public.current_username())
      )
    )
  );

CREATE POLICY files_agent_insert ON public.files
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

-- -------------------- AUDIT LOG (admin read-only) --------------------
CREATE POLICY audit_log_admin_read ON public.audit_log
  FOR SELECT USING (public.current_user_role() = 'admin');

-- -------------------- USER PREFERENCES --------------------
CREATE POLICY user_prefs_own ON public.user_preferences
  FOR ALL USING (username = public.current_username());

-- -------------------- LOGIN ATTEMPTS --------------------
CREATE POLICY login_attempts_admin_read ON public.login_attempts
  FOR SELECT USING (public.current_user_role() = 'admin');

-- Allow inserts from service role / functions (no user-level insert policy needed;
-- login attempts are written by server-side functions with SECURITY DEFINER).

-- -------------------- OTP CODES --------------------
CREATE POLICY otp_codes_admin_read ON public.otp_codes
  FOR SELECT USING (public.current_user_role() = 'admin');

CREATE POLICY otp_codes_own_read ON public.otp_codes
  FOR SELECT USING (username = public.current_username());

-- -------------------- RECORD HISTORY --------------------
CREATE POLICY record_history_admin_all ON public.record_history
  FOR ALL USING (public.current_user_role() = 'admin');

CREATE POLICY record_history_agent_select ON public.record_history
  FOR SELECT USING (
    public.current_user_role() = 'agent'
    AND (
      changed_by = public.current_username()
      OR EXISTS (
        SELECT 1 FROM public.leads   WHERE leads.id   = record_history.record_id AND (leads.agent = public.current_username() OR leads.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.deals   WHERE deals.id   = record_history.record_id AND (deals.executor = public.current_username() OR deals.created_by = public.current_username())
      )
      OR EXISTS (
        SELECT 1 FROM public.clients WHERE clients.id = record_history.record_id AND (clients.advisor = public.current_username() OR clients.created_by = public.current_username())
      )
    )
  );

CREATE POLICY record_history_agent_insert ON public.record_history
  FOR INSERT WITH CHECK (public.current_user_role() = 'agent');

-- ============================================================
-- 16. SEED DATA — 3 USERS
-- ============================================================
INSERT INTO public.users (username, password_hash, display_name, role, phone, email, id_number, avatar, color, role_label)
VALUES
  ('roi',   crypt('changeme', gen_salt('bf')), 'רועי עובדיה', 'admin', '972526569844', 'roi@roibusiness.co.il',   '318686540', 'ר', '#EEBD2A', 'מנהל מערכת'),
  ('natan', crypt('changeme', gen_salt('bf')), 'נתן',          'agent', '972504744114', 'natan@roibusiness.co.il', '211870100', 'נ', '#10b981', 'יועץ מחירות'),
  ('ben',   crypt('changeme', gen_salt('bf')), 'בן',           'agent', '972523817637', 'ben@roibusiness.co.il',   '322230731', 'ב', '#f59e0b', 'יועץ מחירות')
ON CONFLICT (username) DO NOTHING;

-- ============================================================
-- 17. GRANT PERMISSIONS TO anon AND authenticated ROLES
-- ============================================================
-- The anon role needs SELECT on users and INSERT on login_attempts / otp_codes for auth flow.
-- The authenticated role gets full DML on data tables (RLS restricts actual access).

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Anon: limited access for login flow
GRANT SELECT ON public.users TO anon;
GRANT INSERT ON public.login_attempts TO anon;
GRANT INSERT, SELECT, UPDATE ON public.otp_codes TO anon;

-- Authenticated: full DML on all data tables (RLS enforces row-level access)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.deals TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.meetings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.record_tasks TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.files TO authenticated;
GRANT SELECT ON public.audit_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;
GRANT SELECT, INSERT ON public.record_history TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.audit_log_id_seq TO authenticated;

-- ============================================================
-- DONE
-- ============================================================
