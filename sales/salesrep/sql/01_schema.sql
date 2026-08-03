-- ============================================================
-- ABSOLUTE FRESH FOOD — Fresh Start Schema
-- Paste into Supabase SQL Editor → Run
-- ============================================================

-- Enums
CREATE TYPE user_role       AS ENUM ('admin','rep','driver');
CREATE TYPE outlet_status   AS ENUM ('prospect','active','inactive');
CREATE TYPE order_status    AS ENUM ('pending','delivered','cancelled');
CREATE TYPE payment_mode    AS ENUM ('cash','upi','credit','cheque');
CREATE TYPE visit_frequency AS ENUM ('weekly','fortnightly','monthly','adhoc');
CREATE TYPE visit_status    AS ENUM ('planned','completed','missed');
CREATE TYPE beat_plan_status AS ENUM ('draft','published','archived');

-- Users
CREATE TABLE public.users (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  role       user_role NOT NULL DEFAULT 'rep',
  area       TEXT,
  phone      TEXT,
  is_active  BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, name, role, is_active)
  VALUES (
    NEW.id, NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email,'@',1)),
    'rep', false
  ) ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Products
CREATE TABLE public.products (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  unit       TEXT NOT NULL DEFAULT 'kg',
  base_price NUMERIC(10,2) NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Outlets
CREATE TABLE public.outlets (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  area       TEXT NOT NULL,
  owner_name TEXT,
  phone      TEXT,
  rep_id     UUID REFERENCES public.users(id) ON DELETE SET NULL,
  avg_kg_day NUMERIC(6,2) DEFAULT 0,
  status     outlet_status NOT NULL DEFAULT 'active',
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Monthly beat plans
CREATE TABLE public.monthly_beat_plans (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rep_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  month        DATE NOT NULL,
  status       beat_plan_status NOT NULL DEFAULT 'draft',
  published_at TIMESTAMPTZ,
  notes        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (rep_id, month)
);

CREATE TABLE public.monthly_beat_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  monthly_plan_id UUID NOT NULL REFERENCES public.monthly_beat_plans(id) ON DELETE CASCADE,
  outlet_id       UUID NOT NULL REFERENCES public.outlets(id),
  visit_frequency visit_frequency NOT NULL DEFAULT 'weekly',
  preferred_days  TEXT[] NOT NULL DEFAULT '{}',
  target_kg       NUMERIC(6,2) NOT NULL DEFAULT 0,
  visit_sequence  INTEGER NOT NULL DEFAULT 1,
  notes           TEXT,
  UNIQUE (monthly_plan_id, outlet_id)
);

-- Weekly beat plans
CREATE TABLE public.weekly_beat_plans (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rep_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  week_start      DATE NOT NULL,
  monthly_plan_id UUID REFERENCES public.monthly_beat_plans(id),
  is_modified     BOOLEAN NOT NULL DEFAULT false,
  confirmed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (rep_id, week_start)
);

CREATE TABLE public.weekly_beat_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  weekly_plan_id UUID NOT NULL REFERENCES public.weekly_beat_plans(id) ON DELETE CASCADE,
  monthly_item_id UUID REFERENCES public.monthly_beat_items(id),
  outlet_id      UUID NOT NULL REFERENCES public.outlets(id),
  day            TEXT NOT NULL,
  visit_sequence INTEGER NOT NULL DEFAULT 1,
  target_kg      NUMERIC(6,2) NOT NULL DEFAULT 0,
  UNIQUE (weekly_plan_id, outlet_id, day)
);

-- Daily beat logs
CREATE TABLE public.daily_beat_logs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rep_id         UUID NOT NULL REFERENCES public.users(id),
  date           DATE NOT NULL DEFAULT CURRENT_DATE,
  weekly_item_id UUID REFERENCES public.weekly_beat_items(id),
  outlet_id      UUID NOT NULL REFERENCES public.outlets(id),
  visit_sequence INTEGER NOT NULL DEFAULT 1,
  target_kg      NUMERIC(6,2) DEFAULT 0,
  status         visit_status NOT NULL DEFAULT 'planned',
  order_id       UUID,
  visited_at     TIMESTAMPTZ,
  UNIQUE (rep_id, date, outlet_id)
);

-- Orders
CREATE TABLE public.orders (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id  UUID NOT NULL REFERENCES public.outlets(id),
  rep_id     UUID NOT NULL REFERENCES public.users(id),
  date       DATE NOT NULL DEFAULT CURRENT_DATE,
  status     order_status NOT NULL DEFAULT 'pending',
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (outlet_id, date)
);

CREATE TABLE public.order_items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id       UUID NOT NULL REFERENCES public.products(id),
  kg_ordered       NUMERIC(6,2) NOT NULL CHECK (kg_ordered > 0),
  unit_price       NUMERIC(10,2) NOT NULL,
  discount_amount  NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Deliveries
CREATE TABLE public.deliveries (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       UUID NOT NULL UNIQUE REFERENCES public.orders(id),
  driver_id      UUID NOT NULL REFERENCES public.users(id),
  cash_collected NUMERIC(10,2) NOT NULL DEFAULT 0,
  payment_mode   payment_mode NOT NULL DEFAULT 'cash',
  delivered_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.delivery_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id   UUID NOT NULL REFERENCES public.deliveries(id) ON DELETE CASCADE,
  order_item_id UUID NOT NULL REFERENCES public.order_items(id),
  kg_delivered  NUMERIC(6,2) NOT NULL CHECK (kg_delivered >= 0),
  short_reason  TEXT
);

-- Prospects
CREATE TABLE public.prospects (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  area       TEXT NOT NULL,
  owner_name TEXT,
  phone      TEXT,
  notes      TEXT,
  added_by   UUID NOT NULL REFERENCES public.users(id),
  status     TEXT NOT NULL DEFAULT 'new',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- App settings
CREATE TABLE public.app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Default settings
INSERT INTO public.app_settings (key, value) VALUES
  ('overdue_flag_time',     '16:00'),
  ('beat_confirm_deadline', '09:00'),
  ('whatsapp_number',       '');

-- Seed first product
INSERT INTO public.products (name, unit, base_price, is_active)
VALUES ('Dosa Batter', 'kg', 100.00, true);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
ALTER PUBLICATION supabase_realtime ADD TABLE public.deliveries;
ALTER PUBLICATION supabase_realtime ADD TABLE public.daily_beat_logs;

-- ============================================================
-- DONE. Now:
-- 1. Go to Authentication → Users → Add user
--    Email: admin@absolutefreshfood.com
--    Password: Admin@123
--    ✅ Tick "Auto Confirm User"
-- 2. Run the seed_admin.sql below
-- ============================================================


-- ── Auto-rollover beat plans (run on 1st of each month) ───
CREATE OR REPLACE FUNCTION public.rollover_beat_plans()
RETURNS json AS $$
DECLARE
  v_rep RECORD;
  v_prev_plan_id UUID;
  v_new_plan_id  UUID;
  v_count INTEGER := 0;
  v_month DATE := date_trunc('month', CURRENT_DATE)::date;
BEGIN
  FOR v_rep IN SELECT id FROM public.users WHERE role='rep' AND is_active=true
  LOOP
    -- Skip if plan already exists for this month
    IF EXISTS (SELECT 1 FROM monthly_beat_plans WHERE rep_id=v_rep.id AND month=v_month) THEN
      CONTINUE;
    END IF;

    -- Get last month's published plan
    SELECT id INTO v_prev_plan_id
    FROM monthly_beat_plans
    WHERE rep_id=v_rep.id AND status='published'
    ORDER BY month DESC LIMIT 1;

    IF v_prev_plan_id IS NULL THEN CONTINUE; END IF;

    -- Create new draft plan for this month
    INSERT INTO monthly_beat_plans (rep_id, month, status, updated_at)
    VALUES (v_rep.id, v_month, 'draft', NOW())
    RETURNING id INTO v_new_plan_id;

    -- Copy all items from previous plan
    INSERT INTO monthly_beat_items
      (monthly_plan_id, outlet_id, visit_frequency, preferred_days, target_kg, visit_sequence)
    SELECT v_new_plan_id, outlet_id, visit_frequency, preferred_days, target_kg, visit_sequence
    FROM monthly_beat_items WHERE monthly_plan_id=v_prev_plan_id;

    v_count := v_count + 1;
  END LOOP;
  RETURN json_build_object('plans_rolled_over', v_count, 'month', v_month);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Run this on 1st of each month (set up a cron job in Supabase):
-- SELECT public.rollover_beat_plans();
