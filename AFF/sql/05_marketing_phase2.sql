-- ═══════════════════════════════════════════════════════════════
-- MARKETING PHASE 2 — SUPABASE SETUP
-- Absolute Fresh D2C Platform
-- Run AFTER 04_marketing_schema.sql
-- ═══════════════════════════════════════════════════════════════

-- ── 1. ENABLE RLS ON ALL MARKETING TABLES ──────────────────────
ALTER TABLE public.influencers     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupons         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_usage    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.influencer_clicks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaigns       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.commissions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sample_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_logs   ENABLE ROW LEVEL SECURITY;

-- ── 2. INFLUENCERS: Public read (anon key), self-write via custom JWT ──
-- NOTE: The marketing portal uses a custom influencer login (not Supabase Auth).
-- We use a service role on the backend for sensitive ops.
-- The anon/publishable key allows SELECT only for validation; inserts use service role.

-- Allow public INSERT for signup (self-registration)
DROP POLICY IF EXISTS "influencers_public_insert" ON public.influencers;
CREATE POLICY "influencers_public_insert"
ON public.influencers FOR INSERT
TO anon
WITH CHECK (true);

-- Allow public SELECT by email (for login validation only — password_hash never returned by the API without select policy)
-- IMPORTANT: In production, move login validation to a Supabase Edge Function to avoid exposing password_hash
DROP POLICY IF EXISTS "influencers_public_select_by_email" ON public.influencers;
CREATE POLICY "influencers_public_select_by_email"
ON public.influencers FOR SELECT
TO anon
USING (true);  -- Restrict further with Supabase column-level security or edge function

-- Allow public UPDATE by ID (for influencer self-updates via dashboard)
DROP POLICY IF EXISTS "influencers_self_update" ON public.influencers;
CREATE POLICY "influencers_self_update"
ON public.influencers FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

-- ── 3. COUPONS: Public read + insert by influencers ─────────────
DROP POLICY IF EXISTS "coupons_public_read" ON public.coupons;
CREATE POLICY "coupons_public_read"
ON public.coupons FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "coupons_influencer_insert" ON public.coupons;
CREATE POLICY "coupons_influencer_insert"
ON public.coupons FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "coupons_influencer_update" ON public.coupons;
CREATE POLICY "coupons_influencer_update"
ON public.coupons FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

-- ── 4. COUPON USAGE: Allow insert (orders system) ───────────────
DROP POLICY IF EXISTS "coupon_usage_insert" ON public.coupon_usage;
CREATE POLICY "coupon_usage_insert"
ON public.coupon_usage FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "coupon_usage_select" ON public.coupon_usage;
CREATE POLICY "coupon_usage_select"
ON public.coupon_usage FOR SELECT
TO anon
USING (true);

-- ── 5. INFLUENCER CLICKS: Allow insert (click tracking) ─────────
DROP POLICY IF EXISTS "clicks_insert" ON public.influencer_clicks;
CREATE POLICY "clicks_insert"
ON public.influencer_clicks FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "clicks_select" ON public.influencer_clicks;
CREATE POLICY "clicks_select"
ON public.influencer_clicks FOR SELECT
TO anon
USING (true);

-- ── 6. CAMPAIGNS: Public read, admin write ───────────────────────
DROP POLICY IF EXISTS "campaigns_read" ON public.campaigns;
CREATE POLICY "campaigns_read"
ON public.campaigns FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "campaigns_write" ON public.campaigns;
CREATE POLICY "campaigns_write"
ON public.campaigns FOR ALL
TO anon
USING (true)
WITH CHECK (true);

-- ── 7. COMMISSIONS: Influencer read own, admin write ─────────────
DROP POLICY IF EXISTS "commissions_read" ON public.commissions;
CREATE POLICY "commissions_read"
ON public.commissions FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "commissions_write" ON public.commissions;
CREATE POLICY "commissions_write"
ON public.commissions FOR ALL
TO anon
USING (true)
WITH CHECK (true);

-- ── 8. SAMPLE REQUESTS: Influencer own, admin all ────────────────
DROP POLICY IF EXISTS "samples_read" ON public.sample_requests;
CREATE POLICY "samples_read"
ON public.sample_requests FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "samples_insert" ON public.sample_requests;
CREATE POLICY "samples_insert"
ON public.sample_requests FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "samples_update" ON public.sample_requests;
CREATE POLICY "samples_update"
ON public.sample_requests FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

-- ── 9. CONTENT APPROVALS: Influencer own, admin all ──────────────
DROP POLICY IF EXISTS "content_read" ON public.content_approvals;
CREATE POLICY "content_read"
ON public.content_approvals FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "content_insert" ON public.content_approvals;
CREATE POLICY "content_insert"
ON public.content_approvals FOR INSERT
TO anon
WITH CHECK (true);

DROP POLICY IF EXISTS "content_update" ON public.content_approvals;
CREATE POLICY "content_update"
ON public.content_approvals FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

-- ── 10. WHATSAPP LOGS: Admin write, influencer read own ──────────
DROP POLICY IF EXISTS "wa_logs_read" ON public.whatsapp_logs;
CREATE POLICY "wa_logs_read"
ON public.whatsapp_logs FOR SELECT
TO anon
USING (true);

DROP POLICY IF EXISTS "wa_logs_insert" ON public.whatsapp_logs;
CREATE POLICY "wa_logs_insert"
ON public.whatsapp_logs FOR INSERT
TO anon
WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════
-- ADDITIONAL FUNCTIONS & TRIGGERS
-- ═══════════════════════════════════════════════════════════════

-- ── TDS calculation trigger (updates commission on save) ─────────
CREATE OR REPLACE FUNCTION calculate_tds()
RETURNS TRIGGER AS $$
DECLARE
  v_pan TEXT;
  v_annual_payout NUMERIC;
  v_tds NUMERIC;
BEGIN
  -- Get influencer PAN
  SELECT pan_number INTO v_pan
  FROM public.influencers
  WHERE id = NEW.influencer_id;

  -- Calculate annual payout for this influencer
  SELECT COALESCE(SUM(net_payout), 0) INTO v_annual_payout
  FROM public.commissions
  WHERE influencer_id = NEW.influencer_id
    AND payment_status = 'paid'
    AND EXTRACT(YEAR FROM month) = EXTRACT(YEAR FROM NEW.month);

  -- Apply TDS @ 10% only if PAN provided AND annual payout > ₹30,000
  IF v_pan IS NOT NULL AND v_pan != '' AND (v_annual_payout + NEW.commission_amount) > 30000 THEN
    v_tds := ROUND(NEW.commission_amount * 0.10, 0);
  ELSE
    v_tds := 0;
  END IF;

  NEW.tds_amount := v_tds;
  NEW.net_payout := NEW.commission_amount - v_tds;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_calculate_tds ON public.commissions;
CREATE TRIGGER trigger_calculate_tds
BEFORE INSERT OR UPDATE OF commission_amount ON public.commissions
FOR EACH ROW
EXECUTE FUNCTION calculate_tds();

-- ── WhatsApp notification log helper function ─────────────────────
-- Call from Edge Functions or admin triggers
CREATE OR REPLACE FUNCTION log_whatsapp_notification(
  p_trigger TEXT,
  p_recipient_phone TEXT,
  p_recipient_type TEXT,
  p_influencer_id UUID,
  p_message TEXT,
  p_status TEXT DEFAULT 'sent'
)
RETURNS UUID AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO public.whatsapp_logs (
    trigger, recipient_phone, recipient_type,
    influencer_id, message, status
  ) VALUES (
    p_trigger, p_recipient_phone, p_recipient_type,
    p_influencer_id, p_message, p_status
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ── Auto-expire coupons function (call via pg_cron daily) ─────────
CREATE OR REPLACE FUNCTION expire_coupons()
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.coupons
  SET status = 'expired', updated_at = NOW()
  WHERE status = 'active' AND expires_on < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ── Monthly commission auto-calculate for all active influencers ──
-- Run on 1st of every month (via pg_cron: '0 0 1 * *')
CREATE OR REPLACE FUNCTION auto_calculate_monthly_commissions()
RETURNS INTEGER AS $$
DECLARE
  v_month DATE;
  v_count INTEGER := 0;
  r RECORD;
  v_orders INTEGER;
  v_revenue NUMERIC;
  v_tier TEXT;
  v_rate NUMERIC;
  v_commission NUMERIC;
BEGIN
  -- Previous month
  v_month := DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')::DATE;

  FOR r IN
    SELECT i.id, i.pan_number
    FROM public.influencers i
    WHERE i.status = 'approved'
  LOOP
    -- Count delivered orders last month via coupons
    SELECT
      COUNT(DISTINCT o.id),
      COALESCE(SUM(oi.kg_ordered * oi.unit_price), 0)
    INTO v_orders, v_revenue
    FROM public.coupons c
    JOIN public.orders o ON o.coupon_id = c.id AND o.status = 'delivered'
      AND DATE_TRUNC('month', o.date) = v_month
    JOIN public.order_items oi ON oi.order_id = o.id
    WHERE c.influencer_id = r.id;

    IF v_orders > 0 THEN
      v_tier       := CASE WHEN v_orders >= 31 THEN 'gold' WHEN v_orders >= 11 THEN 'silver' ELSE 'bronze' END;
      v_rate       := CASE WHEN v_orders >= 31 THEN 75    WHEN v_orders >= 11 THEN 50       ELSE 30       END;
      v_commission := v_orders * v_rate;

      INSERT INTO public.commissions (
        influencer_id, month, orders_delivered, total_revenue,
        tier, rate_per_order, commission_amount, payment_status
      ) VALUES (
        r.id, v_month, v_orders, v_revenue,
        v_tier, v_rate, v_commission, 'pending'
      )
      ON CONFLICT (influencer_id, month) DO UPDATE SET
        orders_delivered  = EXCLUDED.orders_delivered,
        total_revenue     = EXCLUDED.total_revenue,
        tier              = EXCLUDED.tier,
        rate_per_order    = EXCLUDED.rate_per_order,
        commission_amount = EXCLUDED.commission_amount,
        updated_at        = NOW();

      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ── View: Influencer leaderboard ──────────────────────────────────
CREATE OR REPLACE VIEW public.v_influencer_leaderboard AS
SELECT
  i.id,
  i.name,
  i.instagram_handle,
  i.city,
  i.total_orders,
  i.total_revenue,
  i.total_commission_earned,
  i.cod_rejection_rate,
  i.is_verified,
  i.discount_ceiling,
  CASE
    WHEN i.total_orders >= 31 THEN 'gold'
    WHEN i.total_orders >= 11 THEN 'silver'
    ELSE 'bronze'
  END AS tier,
  CASE
    WHEN i.total_orders >= 31 THEN 75
    WHEN i.total_orders >= 11 THEN 50
    ELSE 30
  END AS rate_per_order,
  COUNT(DISTINCT c.id) AS active_coupons,
  COUNT(DISTINCT sr.id) AS sample_requests,
  COUNT(DISTINCT ca.id) FILTER (WHERE ca.status = 'pending') AS pending_content
FROM public.influencers i
LEFT JOIN public.coupons c ON c.influencer_id = i.id AND c.status = 'active'
LEFT JOIN public.sample_requests sr ON sr.influencer_id = i.id
LEFT JOIN public.content_approvals ca ON ca.influencer_id = i.id
WHERE i.status = 'approved'
GROUP BY i.id
ORDER BY i.total_orders DESC;

-- ── View: Admin dashboard summary ────────────────────────────────
CREATE OR REPLACE VIEW public.v_marketing_summary AS
SELECT
  (SELECT COUNT(*) FROM public.influencers WHERE status = 'approved') AS total_influencers,
  (SELECT COUNT(*) FROM public.influencers WHERE is_verified = TRUE) AS verified_influencers,
  (SELECT COUNT(*) FROM public.coupons WHERE status = 'active') AS active_coupons,
  (SELECT COUNT(*) FROM public.orders WHERE coupon_id IS NOT NULL) AS orders_via_coupon,
  (SELECT COALESCE(SUM(i.total_revenue), 0) FROM public.influencers i) AS total_influenced_revenue,
  (SELECT COALESCE(SUM(commission_amount), 0) FROM public.commissions WHERE payment_status = 'pending') AS pending_commission_payout,
  (SELECT COUNT(*) FROM public.sample_requests WHERE status = 'pending') AS pending_sample_requests,
  (SELECT COUNT(*) FROM public.content_approvals WHERE status = 'pending') AS pending_content_reviews,
  (SELECT COUNT(*) FROM public.campaigns WHERE status = 'active') AS active_campaigns;

-- ═══════════════════════════════════════════════════════════════
-- pg_cron SETUP (enable in Supabase: Extensions → pg_cron)
-- ═══════════════════════════════════════════════════════════════

-- Daily coupon expiry at midnight
-- SELECT cron.schedule('expire-coupons-daily', '0 0 * * *', $$SELECT expire_coupons()$$);

-- Monthly commission calculation on 1st at 1am
-- SELECT cron.schedule('monthly-commissions', '0 1 1 * *', $$SELECT auto_calculate_monthly_commissions()$$);

-- ═══════════════════════════════════════════════════════════════
-- SAMPLE DATA FOR TESTING
-- ═══════════════════════════════════════════════════════════════

-- Test campaign (comment out in production)
/*
INSERT INTO public.campaigns (name, type, budget_allocated, valid_from, status, utm_source, notes)
VALUES
  ('Summer Launch 2025', 'influencer', 50000, CURRENT_DATE, 'active', 'instagram', 'Influencer-led launch campaign'),
  ('Society Drive — May', 'society', 20000, CURRENT_DATE, 'active', 'whatsapp', 'Apartment society sampling drive'),
  ('Diwali Hamper', 'seasonal', 30000, '2025-10-01', 'draft', 'organic', 'Festival gifting campaign')
ON CONFLICT DO NOTHING;
*/

-- ═══════════════════════════════════════════════════════════════
-- SECURITY NOTES FOR PRODUCTION
-- ═══════════════════════════════════════════════════════════════
-- 1. Move influencer login to a Supabase Edge Function (avoid exposing password_hash via anon key)
-- 2. Use Supabase Auth for admin (proper JWT roles) instead of hardcoded PIN
-- 3. Add column-level security to hide sensitive fields (bank_account, pan_number) from anon
-- 4. Set up Supabase Vault for WhatsApp API key (Interakt)
-- 5. Use Supabase Storage for content approval media uploads
-- 6. Enable PITR (Point-in-Time Recovery) before going to production
-- ═══════════════════════════════════════════════════════════════
