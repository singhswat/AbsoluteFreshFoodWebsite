-- ═══════════════════════════════════════════════════════════
-- EXACT GAP FIX — based on production column audit 2026-05-21
-- Only touches what is CONFIRMED MISSING. Safe to re-run.
-- ═══════════════════════════════════════════════════════════

-- ── 1. coupons — 6 missing columns ────────────────────────
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS campaign_id      UUID REFERENCES public.campaigns(id),
  ADD COLUMN IF NOT EXISTS qr_code_url      TEXT,
  ADD COLUMN IF NOT EXISTS max_discount_cap NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS applicable_zones TEXT[],
  ADD COLUMN IF NOT EXISTS is_sample_coupon BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS product_id       UUID REFERENCES public.products(id);

CREATE INDEX IF NOT EXISTS idx_coupons_campaign ON public.coupons(campaign_id);

-- ── 2. orders — 4 missing columns ─────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS customer_email TEXT,
  ADD COLUMN IF NOT EXISTS customer_phone TEXT,
  ADD COLUMN IF NOT EXISTS customer_name  TEXT,
  ADD COLUMN IF NOT EXISTS is_first_order BOOLEAN DEFAULT FALSE;

-- ── 3. whatsapp_logs — rename + 3 missing columns ─────────
-- Production has "recipient" but code expects "recipient_phone"
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'whatsapp_logs'
      AND column_name = 'recipient'
  ) THEN
    ALTER TABLE public.whatsapp_logs RENAME COLUMN recipient TO recipient_phone;
  END IF;
END $$;

ALTER TABLE public.whatsapp_logs
  ADD COLUMN IF NOT EXISTS recipient_type TEXT,
  ADD COLUMN IF NOT EXISTS influencer_id  UUID REFERENCES public.influencers(id),
  ADD COLUMN IF NOT EXISTS error_message  TEXT;

CREATE INDEX IF NOT EXISTS idx_whatsapp_influencer ON public.whatsapp_logs(influencer_id);

-- ── 4. Indexes (safe — IF NOT EXISTS) ─────────────────────
CREATE INDEX IF NOT EXISTS idx_coupons_influencer ON public.coupons(influencer_id);
CREATE INDEX IF NOT EXISTS idx_coupons_status     ON public.coupons(status);
CREATE INDEX IF NOT EXISTS idx_coupons_expiry     ON public.coupons(expires_on);
CREATE INDEX IF NOT EXISTS idx_coupons_code       ON public.coupons(UPPER(code));
CREATE INDEX IF NOT EXISTS idx_commissions_influencer ON public.commissions(influencer_id);
CREATE INDEX IF NOT EXISTS idx_commissions_month      ON public.commissions(month);
CREATE INDEX IF NOT EXISTS idx_commissions_status     ON public.commissions(payment_status);
CREATE INDEX IF NOT EXISTS idx_samples_influencer ON public.sample_requests(influencer_id);
CREATE INDEX IF NOT EXISTS idx_samples_status     ON public.sample_requests(status);
CREATE INDEX IF NOT EXISTS idx_content_influencer ON public.content_approvals(influencer_id);
CREATE INDEX IF NOT EXISTS idx_content_status     ON public.content_approvals(status);
CREATE INDEX IF NOT EXISTS idx_whatsapp_status    ON public.whatsapp_logs(status);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_coupon ON public.coupon_usage(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_order  ON public.coupon_usage(order_id);
CREATE INDEX IF NOT EXISTS idx_clicks_coupon       ON public.influencer_clicks(coupon_id);
CREATE INDEX IF NOT EXISTS idx_clicks_influencer   ON public.influencer_clicks(influencer_id);
CREATE INDEX IF NOT EXISTS idx_orders_coupon       ON public.orders(coupon_id);

-- ── 5. Triggers ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION increment_coupon_usage()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.coupons
    SET times_used = times_used + 1, updated_at = NOW()
    WHERE id = NEW.coupon_id;
  UPDATE public.coupons SET status = 'depleted'
    WHERE id = NEW.coupon_id
      AND usage_limit_total IS NOT NULL
      AND times_used >= usage_limit_total;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_increment_coupon_usage ON public.coupon_usage;
CREATE TRIGGER trigger_increment_coupon_usage
  AFTER INSERT ON public.coupon_usage
  FOR EACH ROW EXECUTE FUNCTION increment_coupon_usage();

CREATE OR REPLACE FUNCTION update_influencer_performance()
RETURNS TRIGGER AS $$
DECLARE
  v_coupon_id     UUID;
  v_influencer_id UUID;
  v_order_value   NUMERIC;
BEGIN
  IF NEW.status::TEXT = 'delivered'
    AND (OLD.status IS NULL OR OLD.status::TEXT != 'delivered') THEN
    v_coupon_id := NEW.coupon_id;
    IF v_coupon_id IS NOT NULL THEN
      SELECT influencer_id INTO v_influencer_id
        FROM public.coupons WHERE id = v_coupon_id;
      IF v_influencer_id IS NOT NULL THEN
        SELECT SUM(kg_ordered * unit_price) INTO v_order_value
          FROM public.order_items WHERE order_id = NEW.id;
        UPDATE public.influencers
          SET total_orders   = total_orders + 1,
              total_revenue  = total_revenue + COALESCE(v_order_value, 0),
              last_active_at = NOW(),
              updated_at     = NOW()
          WHERE id = v_influencer_id;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_influencer_performance ON public.orders;
CREATE TRIGGER trigger_update_influencer_performance
  AFTER UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION update_influencer_performance();

CREATE OR REPLACE FUNCTION expire_coupons()
RETURNS INTEGER AS $$
DECLARE v_count INTEGER;
BEGIN
  UPDATE public.coupons
    SET status = 'expired', updated_at = NOW()
    WHERE status = 'active' AND expires_on < NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ── 6. Views ───────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_influencer_performance AS
SELECT
  i.id, i.name, i.email, i.instagram_handle, i.city, i.status,
  i.is_verified, i.discount_ceiling, i.total_orders, i.total_revenue,
  i.total_commission_earned, i.cod_rejection_rate,
  COUNT(DISTINCT c.id) AS active_coupons,
  SUM(c.times_used)    AS total_coupon_uses,
  MAX(c.updated_at)    AS last_coupon_activity,
  i.created_at         AS joined_at,
  i.last_active_at
FROM public.influencers i
LEFT JOIN public.coupons c ON c.influencer_id = i.id AND c.status = 'active'
GROUP BY i.id;

-- campaign_id now exists on coupons so this view will work
CREATE OR REPLACE VIEW public.v_campaign_roi AS
SELECT
  c.id, c.name, c.type, c.status,
  c.budget_allocated, c.budget_spent, c.revenue_generated,
  CASE WHEN c.budget_spent > 0
    THEN ROUND(((c.revenue_generated - c.budget_spent) / c.budget_spent * 100)::numeric, 2)
    ELSE 0 END AS roi_percentage,
  COUNT(DISTINCT cp.id) AS total_coupons,
  COUNT(DISTINCT cu.id) AS total_redemptions,
  SUM(cu.discount_amount) AS total_discounts_given,
  c.valid_from, c.valid_until
FROM public.campaigns c
LEFT JOIN public.coupons     cp ON cp.campaign_id = c.id
LEFT JOIN public.coupon_usage cu ON cu.coupon_id  = cp.id
GROUP BY c.id;
