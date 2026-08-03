-- ============================================================
-- Run this AFTER creating admin user in Supabase Auth
-- ============================================================

-- Fix admin profile
UPDATE public.users
SET role = 'admin', name = 'Admin', is_active = true
WHERE email = 'admin@absolutefreshfood.com';

-- Verify
SELECT email, name, role, is_active FROM public.users;
