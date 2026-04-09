-- ============================================================
-- Supabase Field Encryption for ROI CRM
-- Run this in the Supabase SQL Editor
-- ============================================================
-- Encrypts sensitive fields (phone, email, amounts) using pgcrypto.
-- Uses trigger-based auto-encryption on INSERT/UPDATE and
-- a decrypt helper function for reading.
-- ============================================================

-- Enable pgcrypto extension
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================
-- 1. ENCRYPTION KEY
-- ============================================================
-- Store the encryption key in a secure table accessible only to postgres role.
-- In production, use Supabase Vault instead.

CREATE TABLE IF NOT EXISTS private.encryption_keys (
  key_name TEXT PRIMARY KEY,
  key_value TEXT NOT NULL
);

-- Create the private schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS private;

-- Revoke all access from public/anon/authenticated
REVOKE ALL ON SCHEMA private FROM PUBLIC;
REVOKE ALL ON SCHEMA private FROM anon;
REVOKE ALL ON SCHEMA private FROM authenticated;

-- Grant usage only to postgres (service role)
GRANT USAGE ON SCHEMA private TO postgres;

-- Recreate the table in private schema
DROP TABLE IF EXISTS private.encryption_keys;
CREATE TABLE private.encryption_keys (
  key_name TEXT PRIMARY KEY,
  key_value TEXT NOT NULL
);

-- Insert the encryption key (change this in production!)
INSERT INTO private.encryption_keys (key_name, key_value)
VALUES ('crm_field_key', 'ROI-CRM-2024-EncryptionKey-!@#$')
ON CONFLICT (key_name) DO UPDATE SET key_value = EXCLUDED.key_value;

-- Only postgres role can access this table
REVOKE ALL ON private.encryption_keys FROM PUBLIC;
REVOKE ALL ON private.encryption_keys FROM anon;
REVOKE ALL ON private.encryption_keys FROM authenticated;
GRANT SELECT ON private.encryption_keys TO postgres;

-- ============================================================
-- 2. ENCRYPT / DECRYPT FUNCTIONS
-- ============================================================

-- Encrypt a text value. Returns hex-encoded encrypted string.
-- Prefix with 'ENC:' so we can detect already-encrypted values.
CREATE OR REPLACE FUNCTION encrypt_field(plain_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER  -- runs as the function owner (postgres), so it can read the key
AS $$
DECLARE
  _key TEXT;
  _encrypted BYTEA;
BEGIN
  IF plain_text IS NULL OR plain_text = '' THEN
    RETURN plain_text;
  END IF;

  -- Don't double-encrypt
  IF plain_text LIKE 'ENC:%' THEN
    RETURN plain_text;
  END IF;

  SELECT key_value INTO _key FROM private.encryption_keys WHERE key_name = 'crm_field_key';

  _encrypted := pgp_sym_encrypt(plain_text, _key);
  RETURN 'ENC:' || encode(_encrypted, 'base64');
END;
$$;

-- Decrypt a text value. Returns plain text.
CREATE OR REPLACE FUNCTION decrypt_field(encrypted_text TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER  -- runs as the function owner (postgres), so it can read the key
AS $$
DECLARE
  _key TEXT;
  _raw BYTEA;
BEGIN
  IF encrypted_text IS NULL OR encrypted_text = '' THEN
    RETURN encrypted_text;
  END IF;

  -- Only decrypt if it starts with our prefix
  IF NOT (encrypted_text LIKE 'ENC:%') THEN
    RETURN encrypted_text;
  END IF;

  SELECT key_value INTO _key FROM private.encryption_keys WHERE key_name = 'crm_field_key';

  _raw := decode(substring(encrypted_text FROM 5), 'base64');
  RETURN pgp_sym_decrypt(_raw, _key);
EXCEPTION
  WHEN OTHERS THEN
    -- If decryption fails, return the raw value (data migration safety)
    RETURN encrypted_text;
END;
$$;

-- ============================================================
-- 3. TRIGGER FUNCTIONS FOR AUTO-ENCRYPTION
-- ============================================================

-- LEADS: encrypt phone, email
CREATE OR REPLACE FUNCTION encrypt_leads_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.phone IS NOT NULL AND NEW.phone != '' AND NOT (NEW.phone LIKE 'ENC:%') THEN
    NEW.phone := encrypt_field(NEW.phone);
  END IF;
  IF NEW.email IS NOT NULL AND NEW.email != '' AND NOT (NEW.email LIKE 'ENC:%') THEN
    NEW.email := encrypt_field(NEW.email);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_encrypt_leads ON public.leads;
CREATE TRIGGER trg_encrypt_leads
  BEFORE INSERT OR UPDATE ON public.leads
  FOR EACH ROW
  EXECUTE FUNCTION encrypt_leads_fields();

-- CLIENTS: encrypt client_phone, client_email
CREATE OR REPLACE FUNCTION encrypt_clients_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.client_phone IS NOT NULL AND NEW.client_phone != '' AND NOT (NEW.client_phone LIKE 'ENC:%') THEN
    NEW.client_phone := encrypt_field(NEW.client_phone);
  END IF;
  IF NEW.client_email IS NOT NULL AND NEW.client_email != '' AND NOT (NEW.client_email LIKE 'ENC:%') THEN
    NEW.client_email := encrypt_field(NEW.client_email);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_encrypt_clients ON public.clients;
CREATE TRIGGER trg_encrypt_clients
  BEFORE INSERT OR UPDATE ON public.clients
  FOR EACH ROW
  EXECUTE FUNCTION encrypt_clients_fields();

-- PAYMENTS: encrypt amount
CREATE OR REPLACE FUNCTION encrypt_payments_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.amount IS NOT NULL AND NEW.amount::TEXT != '' AND NOT (NEW.amount::TEXT LIKE 'ENC:%') THEN
    NEW.amount := encrypt_field(NEW.amount::TEXT);
  END IF;
  RETURN NEW;
END;
$$;

-- NOTE: Only create this trigger if the amount column is TEXT type.
-- If amount is numeric, we need to change the column type first:
-- ALTER TABLE public.payments ALTER COLUMN amount TYPE TEXT;
-- Uncomment the lines below only if amount is TEXT:

-- DROP TRIGGER IF EXISTS trg_encrypt_payments ON public.payments;
-- CREATE TRIGGER trg_encrypt_payments
--   BEFORE INSERT OR UPDATE ON public.payments
--   FOR EACH ROW
--   EXECUTE FUNCTION encrypt_payments_fields();

-- ============================================================
-- 4. DECRYPTED VIEWS FOR READING
-- ============================================================
-- These views auto-decrypt fields so the app can read plain values.
-- The app should SELECT from these views instead of the raw tables.

CREATE OR REPLACE VIEW public.v_leads AS
SELECT
  *,
  decrypt_field(phone) AS phone_plain,
  decrypt_field(email) AS email_plain
FROM public.leads;

CREATE OR REPLACE VIEW public.v_clients AS
SELECT
  *,
  decrypt_field(client_phone) AS client_phone_plain,
  decrypt_field(client_email) AS client_email_plain
FROM public.clients;

-- Grant access to the views
GRANT SELECT ON public.v_leads TO authenticated;
GRANT SELECT ON public.v_clients TO authenticated;

-- ============================================================
-- 5. RPC FUNCTIONS FOR DECRYPTED READS
-- ============================================================
-- Alternative approach: RPC functions that return decrypted data.
-- This is more flexible than views.

CREATE OR REPLACE FUNCTION get_leads_decrypted()
RETURNS TABLE (
  id TEXT, name TEXT, phone TEXT, email TEXT, status TEXT,
  source TEXT, why_contact TEXT, notes TEXT, is_gold BOOLEAN,
  whatsapp_link TEXT, relevant_date TEXT, priority TEXT,
  created_by TEXT, updated_by TEXT, created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    l.id, l.name,
    decrypt_field(l.phone) AS phone,
    decrypt_field(l.email) AS email,
    l.status, l.source, l.why_contact, l.notes, l.is_gold,
    l.whatsapp_link, l.relevant_date, l.priority,
    l.created_by, l.updated_by, l.created_at, l.updated_at
  FROM public.leads l;
END;
$$;

CREATE OR REPLACE FUNCTION get_clients_decrypted()
RETURNS TABLE (
  id TEXT, name TEXT, client_phone TEXT, client_email TEXT,
  client_status TEXT, start_date TEXT, end_date TEXT,
  done_meetings INT, total_meetings INT, deal_id TEXT,
  deal_name TEXT, deal_ref TEXT, lead_name TEXT,
  avg_months_in_process TEXT, advisor_email TEXT, advisor_phone TEXT,
  created_by TEXT, updated_by TEXT, created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.id, c.name,
    decrypt_field(c.client_phone) AS client_phone,
    decrypt_field(c.client_email) AS client_email,
    c.client_status, c.start_date, c.end_date,
    c.done_meetings, c.total_meetings, c.deal_id,
    c.deal_name, c.deal_ref, c.lead_name,
    c.avg_months_in_process, c.advisor_email, c.advisor_phone,
    c.created_by, c.updated_by, c.created_at, c.updated_at
  FROM public.clients c;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_leads_decrypted() TO authenticated;
GRANT EXECUTE ON FUNCTION get_clients_decrypted() TO authenticated;

-- ============================================================
-- 6. ENCRYPT EXISTING DATA (run once after setup)
-- ============================================================
-- This will encrypt all existing plain-text phone/email values.
-- Run this AFTER the triggers are created.
-- WARNING: This is a one-way operation. Back up your data first!

-- Uncomment to run:
-- UPDATE public.leads SET phone = phone, email = email WHERE phone IS NOT NULL AND phone != '' AND NOT (phone LIKE 'ENC:%');
-- UPDATE public.clients SET client_phone = client_phone, client_email = client_email WHERE client_phone IS NOT NULL AND client_phone != '' AND NOT (client_phone LIKE 'ENC:%');

-- ============================================================
-- 7. VERIFY
-- ============================================================
-- Test encryption:
-- SELECT encrypt_field('0526569844');
-- SELECT decrypt_field(encrypt_field('0526569844'));
