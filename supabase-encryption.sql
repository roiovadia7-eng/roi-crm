-- ============================================================
-- Supabase Field Encryption for ROI CRM
-- ALREADY DEPLOYED - This file documents what's running in the DB
-- ============================================================

-- ============================================================
-- 1. PRIVATE SCHEMA + ENCRYPTION KEY
-- ============================================================
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO postgres;

CREATE TABLE IF NOT EXISTS private.encryption_keys (
  key_name TEXT PRIMARY KEY,
  key_value TEXT NOT NULL
);
-- Key inserted: 'crm_field_key'
REVOKE ALL ON private.encryption_keys FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.encryption_keys TO postgres;

-- ============================================================
-- 2. API KEYS (Green API credentials - server-side only)
-- ============================================================
CREATE TABLE IF NOT EXISTS private.api_keys (
  key_name TEXT PRIMARY KEY,
  key_value TEXT NOT NULL
);
-- Keys: green_api_instance, green_api_token
REVOKE ALL ON private.api_keys FROM PUBLIC, anon, authenticated;
GRANT SELECT ON private.api_keys TO postgres;

-- ============================================================
-- 3. ENCRYPT / DECRYPT FUNCTIONS (SECURITY DEFINER)
-- ============================================================
CREATE OR REPLACE FUNCTION encrypt_field(plain_text TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE _key TEXT; _encrypted BYTEA;
BEGIN
  IF plain_text IS NULL OR plain_text = '' THEN RETURN plain_text; END IF;
  IF plain_text LIKE 'ENC:%' THEN RETURN plain_text; END IF;
  SELECT key_value INTO _key FROM private.encryption_keys WHERE key_name = 'crm_field_key';
  _encrypted := pgp_sym_encrypt(plain_text, _key);
  RETURN 'ENC:' || encode(_encrypted, 'base64');
END; $$;

CREATE OR REPLACE FUNCTION decrypt_field(encrypted_text TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE _key TEXT; _raw BYTEA;
BEGIN
  IF encrypted_text IS NULL OR encrypted_text = '' THEN RETURN encrypted_text; END IF;
  IF NOT (encrypted_text LIKE 'ENC:%') THEN RETURN encrypted_text; END IF;
  SELECT key_value INTO _key FROM private.encryption_keys WHERE key_name = 'crm_field_key';
  _raw := decode(substring(encrypted_text FROM 5), 'base64');
  RETURN pgp_sym_decrypt(_raw, _key);
EXCEPTION WHEN OTHERS THEN RETURN encrypted_text;
END; $$;

-- ============================================================
-- 4. AUTO-ENCRYPTION TRIGGERS
-- ============================================================
-- Leads: phone, email
CREATE OR REPLACE FUNCTION encrypt_leads_fields() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.phone IS NOT NULL AND NEW.phone != '' AND NOT (NEW.phone LIKE 'ENC:%') THEN NEW.phone := encrypt_field(NEW.phone); END IF;
  IF NEW.email IS NOT NULL AND NEW.email != '' AND NOT (NEW.email LIKE 'ENC:%') THEN NEW.email := encrypt_field(NEW.email); END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_encrypt_leads BEFORE INSERT OR UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION encrypt_leads_fields();

-- Clients: client_phone, client_email
CREATE OR REPLACE FUNCTION encrypt_clients_fields() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.client_phone IS NOT NULL AND NEW.client_phone != '' AND NOT (NEW.client_phone LIKE 'ENC:%') THEN NEW.client_phone := encrypt_field(NEW.client_phone); END IF;
  IF NEW.client_email IS NOT NULL AND NEW.client_email != '' AND NOT (NEW.client_email LIKE 'ENC:%') THEN NEW.client_email := encrypt_field(NEW.client_email); END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_encrypt_clients BEFORE INSERT OR UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION encrypt_clients_fields();

-- Deals: credit_details
CREATE OR REPLACE FUNCTION encrypt_deals_fields() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.credit_details IS NOT NULL AND NEW.credit_details != '' AND NOT (NEW.credit_details LIKE 'ENC:%') THEN NEW.credit_details := encrypt_field(NEW.credit_details); END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_encrypt_deals BEFORE INSERT OR UPDATE ON public.deals FOR EACH ROW EXECUTE FUNCTION encrypt_deals_fields();

-- ============================================================
-- 5. DECRYPTED RPC FUNCTIONS (app reads through these)
-- ============================================================
-- get_leads_decrypted() - returns leads with phone/email decrypted
-- get_clients_decrypted() - returns clients with client_phone/client_email decrypted
-- get_deals_decrypted() - returns deals with credit_details decrypted
-- All granted to authenticated role

-- ============================================================
-- 6. SERVER-SIDE OTP SENDING
-- ============================================================
-- send_whatsapp_otp(p_phone TEXT, p_otp TEXT) - uses pg_net + private.api_keys
-- Granted to authenticated role

-- ============================================================
-- 7. RLS POLICIES (role-based)
-- ============================================================
-- Data tables (leads, deals, clients, payments, products, meetings, tasks,
--   notes, record_tasks, record_history, files):
--   SELECT: all authenticated
--   INSERT: all authenticated
--   UPDATE: all authenticated
--   DELETE: admin only (jwt -> user_metadata ->> 'role' = 'admin')
--
-- users: SELECT all, INSERT/UPDATE/DELETE admin only
-- audit_log: SELECT all, INSERT all
-- user_preferences: own username only (via JWT)
-- login_attempts, otp_codes: all authenticated
