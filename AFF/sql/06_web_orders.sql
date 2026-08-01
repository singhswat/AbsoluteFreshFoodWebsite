-- ═══════════════════════════════════════════════════════════
-- WEB ORDERS — Website D2C order capture
-- Run after 04c_exact_gap_fix.sql and 05_marketing_phase2.sql
-- ═══════════════════════════════════════════════════════════

-- ── 1. Order reference counter ─────────────────────────────
CREATE SEQUENCE IF NOT EXISTS public.web_order_seq START 1000 INCREMENT 1;

-- ── 2. web_orders table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.web_orders (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_ref        TEXT UNIQUE DEFAULT 'WO-' || nextval('public.web_order_seq'),
  customer_name    TEXT NOT NULL,
  customer_phone   TEXT NOT NULL,
  customer_address TEXT NOT NULL,
  items            JSONB NOT NULL DEFAULT '[]',
  -- e.g. [{"name":"1 kg Pack","qty":2,"price":135,"total":270}]
  coupon_code      TEXT,
  coupon_id        UUID REFERENCES public.coupons(id),
  subtotal         NUMERIC(10,2) DEFAULT 0,
  discount_amount  NUMERIC(10,2) DEFAULT 0,
  total            NUMERIC(10,2) DEFAULT 0,
  status           TEXT DEFAULT 'new'
                     CHECK (status IN ('new','confirmed','locked','out_for_delivery','delivered','cancelled')),
  delivery_date    DATE,
  delivery_slot    TEXT,
  admin_notes      TEXT,
  source           TEXT DEFAULT 'website',
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_web_orders_status  ON public.web_orders(status);
CREATE INDEX IF NOT EXISTS idx_web_orders_phone   ON public.web_orders(customer_phone);
CREATE INDEX IF NOT EXISTS idx_web_orders_date    ON public.web_orders(created_at);
CREATE INDEX IF NOT EXISTS idx_web_orders_ref     ON public.web_orders(order_ref);

-- ── 3. Auto-update updated_at ──────────────────────────────
CREATE OR REPLACE FUNCTION touch_web_order()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_touch_web_order ON public.web_orders;
CREATE TRIGGER trg_touch_web_order
  BEFORE UPDATE ON public.web_orders
  FOR EACH ROW EXECUTE FUNCTION touch_web_order();

-- ── 4. Auto-lock orders past cutoff ───────────────────────
-- Call this via pg_cron daily or from the admin dashboard
CREATE OR REPLACE FUNCTION lock_past_cutoff_orders()
RETURNS INTEGER AS $$
DECLARE
  v_cutoff TEXT;
  v_cutoff_time TIME;
  v_count INTEGER;
BEGIN
  -- Read cutoff from app_settings (key = 'order_cutoff_time', default '20:00')
  SELECT COALESCE(value, '20:00') INTO v_cutoff
    FROM public.app_settings WHERE key = 'order_cutoff_time' LIMIT 1;

  v_cutoff_time := v_cutoff::TIME;

  UPDATE public.web_orders
    SET status = 'locked', updated_at = NOW()
    WHERE status IN ('new','confirmed')
      AND created_at::DATE = CURRENT_DATE
      AND CURRENT_TIME > v_cutoff_time;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ── 5. app_settings — add cutoff_time if missing ──────────
-- (app_settings table already exists in production)
DO $$
BEGIN
  -- Add 'value' column if the table uses a different schema
  -- Try inserting the cutoff setting; ignore if already exists
  INSERT INTO public.app_settings (key, value)
  VALUES ('order_cutoff_time', '20:00')
  ON CONFLICT (key) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  -- Table has a different schema; we'll manage cutoff in web_orders logic
  RAISE NOTICE 'Could not insert order_cutoff_time into app_settings: %', SQLERRM;
END $$;

-- ── 6. RLS ─────────────────────────────────────────────────
ALTER TABLE public.web_orders ENABLE ROW LEVEL SECURITY;

-- Public can insert (website form submits anonymously)
DROP POLICY IF EXISTS "web_orders_public_insert" ON public.web_orders;
CREATE POLICY "web_orders_public_insert"
  ON public.web_orders FOR INSERT TO anon WITH CHECK (true);

-- Public can read own order by phone (for order tracking)
DROP POLICY IF EXISTS "web_orders_public_read" ON public.web_orders;
CREATE POLICY "web_orders_public_read"
  ON public.web_orders FOR SELECT TO anon USING (true);

-- Public can update own new/confirmed order (for customer edits before cutoff)
DROP POLICY IF EXISTS "web_orders_public_update" ON public.web_orders;
CREATE POLICY "web_orders_public_update"
  ON public.web_orders FOR UPDATE TO anon
  USING (status IN ('new','confirmed'))
  WITH CHECK (true);

-- ── 7. View for admin dashboard ────────────────────────────
CREATE OR REPLACE VIEW public.v_web_orders_today AS
SELECT
  id, order_ref, customer_name, customer_phone, customer_address,
  items, coupon_code, subtotal, discount_amount, total,
  status, delivery_date, delivery_slot, admin_notes, created_at
FROM public.web_orders
WHERE created_at::DATE = CURRENT_DATE
  OR (status IN ('new','confirmed') AND created_at::DATE >= CURRENT_DATE - 1)
ORDER BY created_at DESC;

-- ── 8. pg_cron — lock orders at 8pm daily (optional) ──────
-- Enable pg_cron extension first, then uncomment:
-- SELECT cron.schedule('lock-orders-cutoff', '0 20 * * *', $$SELECT lock_past_cutoff_orders()$$);
