-- ============================================================
-- PRODUCTION SETUP CHECKLIST
-- Run this in your PROD Supabase project
-- ============================================================

-- Step 1: Run 01_schema.sql first (creates all tables)

-- Step 2: Create admin user in Supabase Auth dashboard
-- Authentication → Users → Add user
-- Email: admin@absolutefreshfood.com
-- Password: (strong password, different from dev)
-- ✅ Auto Confirm User

-- Step 3: Run this to activate admin
UPDATE public.users
SET role = 'admin', name = 'Admin', is_active = true
WHERE email = 'admin@absolutefreshfood.com';

-- Step 4: Add your first product
INSERT INTO public.products (name, unit, base_price, is_active)
VALUES ('Dosa Batter', 'kg', 100.00, true);

-- Step 5: Verify
SELECT 'users' as tbl, count(*) FROM public.users
UNION ALL
SELECT 'products', count(*) FROM public.products;

-- ============================================================
-- BEFORE GO LIVE CHECKLIST
-- ============================================================
-- □ Fresh Supabase project created (not the dev one)
-- □ Schema deployed (01_schema.sql)
-- □ Admin user created and activated
-- □ Products added with correct prices
-- □ ACTIVE_ENV = 'prod' in js/app.js
-- □ Prod URL and anon key in ENV.prod in js/app.js
-- □ Files uploaded to Hostinger public_html/
-- □ Test login on live URL before telling team
-- □ Beat plans set up for current month
-- □ Rep and driver accounts created
-- □ Reps trained on mobile flow
-- ============================================================
