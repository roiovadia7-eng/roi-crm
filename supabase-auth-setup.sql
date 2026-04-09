-- ============================================================
-- Supabase Auth Users Setup for ROI CRM
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================
-- This creates 3 auth users that map to the CRM's hardcoded USERS.
-- Default password for all: Roi2024!
-- Each user gets user_metadata with: username, display_name, role, avatar, color, roleLabel
-- ============================================================

-- Enable pgcrypto if not already enabled (needed for bcrypt)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helper: generate a proper UUID v4
-- (Supabase auth.users requires UUID primary keys)

-- ============================================================
-- 1. CREATE AUTH USERS
-- ============================================================
-- We use raw INSERT into auth.users with bcrypt-hashed password.
-- The password "Roi2024!" is hashed with crypt() + gen_salt('bf').

-- Delete existing auth users with these emails if they exist (idempotent)
DELETE FROM auth.users WHERE email IN (
  'roi@roicrm.local',
  'natan@roicrm.local',
  'ben@roicrm.local'
);

-- User 1: roi (admin)
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_user_meta_data, raw_app_meta_data,
  confirmation_token, recovery_token, email_change_token_new,
  is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'roi@roicrm.local',
  crypt('Roi2024!', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  jsonb_build_object(
    'username', 'roi',
    'display_name', 'רועי עובדיה',
    'role', 'admin',
    'roleLabel', 'מנהל מערכת',
    'avatar', 'ר',
    'color', '#EEBD2A',
    'id_number', '318686540',
    'phone', '972526569844',
    'email', 'roi@roibusiness.co.il'
  ),
  jsonb_build_object('provider', 'email', 'providers', ARRAY['email']),
  '', '', '',
  FALSE
);

-- User 2: natan (agent)
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_user_meta_data, raw_app_meta_data,
  confirmation_token, recovery_token, email_change_token_new,
  is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'natan@roicrm.local',
  crypt('Roi2024!', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  jsonb_build_object(
    'username', 'natan',
    'display_name', 'נתן',
    'role', 'agent',
    'roleLabel', 'יועץ מחירות',
    'avatar', 'נ',
    'color', '#10b981',
    'id_number', '211870100',
    'phone', '972504744114',
    'email', 'natan@roibusiness.co.il'
  ),
  jsonb_build_object('provider', 'email', 'providers', ARRAY['email']),
  '', '', '',
  FALSE
);

-- User 3: ben (agent)
INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_user_meta_data, raw_app_meta_data,
  confirmation_token, recovery_token, email_change_token_new,
  is_super_admin
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'ben@roicrm.local',
  crypt('Roi2024!', gen_salt('bf')),
  NOW(), NOW(), NOW(),
  jsonb_build_object(
    'username', 'ben',
    'display_name', 'בן',
    'role', 'agent',
    'roleLabel', 'יועץ מחירות',
    'avatar', 'ב',
    'color', '#f59e0b',
    'id_number', '322230731',
    'phone', '972523817637',
    'email', 'ben@roibusiness.co.il'
  ),
  jsonb_build_object('provider', 'email', 'providers', ARRAY['email']),
  '', '', '',
  FALSE
);

-- ============================================================
-- 2. CREATE IDENTITIES (required for signInWithPassword to work)
-- ============================================================
-- Supabase Auth requires an entry in auth.identities for email/password login.

INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
SELECT
  gen_random_uuid(),
  u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email),
  'email',
  u.id::text,
  NOW(),
  NOW(),
  NOW()
FROM auth.users u
WHERE u.email IN ('roi@roicrm.local', 'natan@roicrm.local', 'ben@roicrm.local')
AND NOT EXISTS (
  SELECT 1 FROM auth.identities i WHERE i.user_id = u.id AND i.provider = 'email'
);

-- ============================================================
-- 3. VERIFY
-- ============================================================
-- Run this to verify the users were created:
SELECT id, email, raw_user_meta_data->>'username' AS username,
       raw_user_meta_data->>'role' AS role,
       raw_user_meta_data->>'display_name' AS display_name,
       email_confirmed_at
FROM auth.users
WHERE email LIKE '%@roicrm.local'
ORDER BY email;
