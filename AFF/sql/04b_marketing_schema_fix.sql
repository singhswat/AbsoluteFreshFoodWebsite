-- ═══════════════════════════════════════════════════════════
-- DEFINITIVE FIX — based on diagnostic 2025-05-21
-- Merges comprehensive column coverage with safe DO $$ guards.
-- Safe to re-run (all statements are idempotent).
-- ═══════════════════════════════════════════════════════════

-- ── 1. Patch coupons — all potentially missing columns ─────
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS campaign_id              UUID REFERENCES public.campaigns(id),
  ADD COLUMN IF NOT EXISTS influencer_id            UUID REFERENCES public.influencers(id),
  ADD COLUMN IF NOT EXISTS short_link               TEXT,
  ADD COLUMN IF NOT EXISTS qr_code_url              TEXT,
  ADD COLUMN IF NOT EXISTS min_order_value          NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_discount_cap         NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS usage_limit_total        INTEGER,
  ADD COLUMN IF NOT EXISTS usage_limit_per_customer INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS times_used               INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS valid_from               TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS expires_on               TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS applicable_zones         TEXT[],
  ADD COLUMN IF NOT EXISTS is_stackable             BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS first_order_only         BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_sample_coupon         BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS created_by               UUID,
  ADD COLUMN IF NOT EXISTS updated_at               TIMESTAMPTZ DEFAULT NOW();

-- product_id on coupons — only add FK if products table exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'coupons' AND column_name = 'product_id'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'products'
    ) THEN
      ALTER TABLE public.coupons ADD COLUMN product_id UUID REFERENCES public.products(id);
    ELSE
      ALTER TABLE public.coupons ADD COLUMN product_id UUID;
    END IF;
  END IF;
END $$;

-- discount_type — must add separately (has NOT NULL + DEFAULT + CHECK)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'coupons' AND column_name = 'discount_type'
  ) THEN
    ALTER TABLE public.coupons
      ADD COLUMN discount_type TEXT NOT NULL DEFAULT 'percentage'
        CHECK (discount_type IN ('percentage','fixed_amount','free_delivery','product_specific'));
  END IF;
END $$;

-- status on coupons — must add separately (has NOT NULL + DEFAULT + CHECK)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'coupons' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.coupons
      ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','paused','expired','depleted'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_coupons_influencer ON public.coupons(influencer_id);
CREATE INDEX IF NOT EXISTS idx_coupons_campaign   ON public.coupons(campaign_id);
CREATE INDEX IF NOT EXISTS idx_coupons_status     ON public.coupons(status);
CREATE INDEX IF NOT EXISTS idx_coupons_expiry     ON public.coupons(expires_on);
CREATE INDEX IF NOT EXISTS idx_coupons_code       ON public.coupons(UPPER(code));

-- ── 2. Patch influencers — all potentially missing columns ─
ALTER TABLE public.influencers
  ADD COLUMN IF NOT EXISTS youtube_url              TEXT,
  ADD COLUMN IF NOT EXISTS facebook_url             TEXT,
  ADD COLUMN IF NOT EXISTS follower_count           INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS content_category         TEXT,
  ADD COLUMN IF NOT EXISTS address                  TEXT,
  ADD COLUMN IF NOT EXISTS pincode                  TEXT,
  ADD COLUMN IF NOT EXISTS is_verified              BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS verified_at              TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS discount_ceiling         NUMERIC(5,2) DEFAULT 25.00,
  ADD COLUMN IF NOT EXISTS total_orders             INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_revenue            NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_commission_earned  NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cod_rejection_count      INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cod_rejection_rate       NUMERIC(5,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bank_account             TEXT,
  ADD COLUMN IF NOT EXISTS ifsc_code                TEXT,
  ADD COLUMN IF NOT EXISTS upi_id                   TEXT,
  ADD COLUMN IF NOT EXISTS pan_number               TEXT,
  ADD COLUMN IF NOT EXISTS applied_at               TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS approved_at              TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_active_at           TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS exclusivity_agreed_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS admin_notes              TEXT,
  ADD COLUMN IF NOT EXISTS updated_at               TIMESTAMPTZ DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_influencers_status   ON public.influencers(status);
CREATE INDEX IF NOT EXISTS idx_influencers_verified ON public.influencers(is_verified);
CREATE INDEX IF NOT EXISTS idx_influencers_city     ON public.influencers(city);

-- ── 3. Patch orders — all potentially missing columns ──────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS coupon_id       UUID REFERENCES public.coupons(id),
  ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS customer_email  TEXT,
  ADD COLUMN IF NOT EXISTS customer_phone  TEXT,
  ADD COLUMN IF NOT EXISTS customer_name   TEXT,
  ADD COLUMN IF NOT EXISTS is_first_order  BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_orders_coupon ON public.orders(coupon_id);

-- ── 4. coupon_usage ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.coupon_usage (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id       UUID NOT NULL REFERENCES public.coupons(id),
  order_id        UUID NOT NULL REFERENCES public.orders(id),
  customer_email  TEXT,
  customer_phone  TEXT,
  order_value     NUMERIC(10,2) NOT NULL,
  discount_amount NUMERIC(10,2) NOT NULL,
  source          TEXT,
  referrer_url    TEXT,
  device_type     TEXT,
  ip_address      INET,
  used_at         TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_coupon ON public.coupon_usage(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_order  ON public.coupon_usage(order_id);
CREATE INDEX IF NOT EXISTS idx_coupon_usage_date   ON public.coupon_usage(used_at);

-- ── 5. influencer_clicks ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.influencer_clicks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id     UUID NOT NULL REFERENCES public.coupons(id),
  influencer_id UUID NOT NULL REFERENCES public.influencers(id),
  clicked_at    TIMESTAMPTZ DEFAULT NOW(),
  referrer_url  TEXT,
  device_type   TEXT,
  ip_address    INET,
  user_agent    TEXT,
  converted     BOOLEAN DEFAULT FALSE,
  order_id      UUID REFERENCES public.orders(id),
  converted_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_clicks_coupon     ON public.influencer_clicks(coupon_id);
CREATE INDEX IF NOT EXISTS idx_clicks_influencer ON public.influencer_clicks(influencer_id);
CREATE INDEX IF NOT EXISTS idx_clicks_date       ON public.influencer_clicks(clicked_at);
CREATE INDEX IF NOT EXISTS idx_clicks_converted  ON public.influencer_clicks(converted);

-- ── 6. commissions ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.commissions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  influencer_id     UUID NOT NULL REFERENCES public.influencers(id),
  month             DATE NOT NULL,
  orders_delivered  INTEGER DEFAULT 0,
  orders_rejected   INTEGER DEFAULT 0,
  total_revenue     NUMERIC(10,2) DEFAULT 0,
  tier              TEXT CHECK (tier IN ('bronze','silver','gold')),
  rate_per_order    NUMERIC(10,2),
  commission_amount NUMERIC(10,2) DEFAULT 0,
  tds_amount        NUMERIC(10,2) DEFAULT 0,
  net_payout        NUMERIC(10,2) DEFAULT 0,
  payment_status    TEXT DEFAULT 'pending'
                      CHECK (payment_status IN ('pending','processing','paid','failed')),
  payment_method    TEXT,
  payment_reference TEXT,
  paid_at           TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(influencer_id, month)
);
CREATE INDEX IF NOT EXISTS idx_commissions_influencer ON public.commissions(influencer_id);
CREATE INDEX IF NOT EXISTS idx_commissions_month      ON public.commissions(month);
CREATE INDEX IF NOT EXISTS idx_commissions_status     ON public.commissions(payment_status);

-- ── 7. sample_requests ─────────────────────────────────────
-- DO block: create if missing, then always patch influencer_id
-- (handles both: table missing entirely, OR table exists without influencer_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'sample_requests'
  ) THEN
    CREATE TABLE public.sample_requests (
      id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      influencer_id          UUID NOT NULL REFERENCES public.influencers(id),
      product_id             TEXT NOT NULL,
      quantity               INTEGER DEFAULT 1,
      delivery_address       TEXT NOT NULL,
      pincode                TEXT,
      content_type           TEXT,
      estimated_posting_date DATE,
      status                 TEXT DEFAULT 'pending'
                               CHECK (status IN ('pending','approved','rejected','delivered','posted')),
      reviewed_by            UUID,
      reviewed_at            TIMESTAMPTZ,
      rejection_reason       TEXT,
      sample_order_id        UUID REFERENCES public.orders(id),
      sample_coupon_id       UUID REFERENCES public.coupons(id),
      delivered_at           TIMESTAMPTZ,
      post_url               TEXT,
      posted_at              TIMESTAMPTZ,
      sample_cost            NUMERIC(10,2),
      requested_at           TIMESTAMPTZ DEFAULT NOW(),
      created_at             TIMESTAMPTZ DEFAULT NOW(),
      updated_at             TIMESTAMPTZ DEFAULT NOW()
    );
  END IF;
END $$;

-- Patch influencer_id if table existed without it
ALTER TABLE public.sample_requests
  ADD COLUMN IF NOT EXISTS influencer_id UUID REFERENCES public.influencers(id);

ALTER TABLE public.sample_requests
  ADD COLUMN IF NOT EXISTS product_id      TEXT,
  ADD COLUMN IF NOT EXISTS quantity        INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS delivery_address TEXT,
  ADD COLUMN IF NOT EXISTS pincode         TEXT,
  ADD COLUMN IF NOT EXISTS content_type    TEXT,
  ADD COLUMN IF NOT EXISTS estimated_posting_date DATE,
  ADD COLUMN IF NOT EXISTS reviewed_by     UUID,
  ADD COLUMN IF NOT EXISTS reviewed_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
  ADD COLUMN IF NOT EXISTS sample_order_id UUID REFERENCES public.orders(id),
  ADD COLUMN IF NOT EXISTS sample_coupon_id UUID REFERENCES public.coupons(id),
  ADD COLUMN IF NOT EXISTS delivered_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS post_url        TEXT,
  ADD COLUMN IF NOT EXISTS posted_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sample_cost     NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS requested_at    TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS created_at      TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ DEFAULT NOW();

-- status on sample_requests — separate because of CHECK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'sample_requests' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.sample_requests
      ADD COLUMN status TEXT DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected','delivered','posted'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_samples_influencer ON public.sample_requests(influencer_id);
CREATE INDEX IF NOT EXISTS idx_samples_status     ON public.sample_requests(status);

-- ── 8. content_approvals ───────────────────────────────────
-- Same DO block pattern: create if missing, then patch columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'content_approvals'
  ) THEN
    CREATE TABLE public.content_approvals (
      id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      influencer_id         UUID NOT NULL REFERENCES public.influencers(id),
      coupon_id             UUID REFERENCES public.coupons(id),
      content_type          TEXT NOT NULL,
      caption               TEXT,
      hashtags              TEXT[],
      media_url             TEXT,
      intended_posting_date TIMESTAMPTZ,
      status                TEXT DEFAULT 'pending'
                              CHECK (status IN ('pending','approved','rejected','changes_requested','posted')),
      reviewed_by           UUID,
      reviewed_at           TIMESTAMPTZ,
      feedback              TEXT,
      auto_approved         BOOLEAN DEFAULT FALSE,
      live_post_url         TEXT,
      posted_at             TIMESTAMPTZ,
      likes                 INTEGER DEFAULT 0,
      comments              INTEGER DEFAULT 0,
      shares                INTEGER DEFAULT 0,
      submitted_at          TIMESTAMPTZ DEFAULT NOW(),
      approval_expires_at   TIMESTAMPTZ,
      created_at            TIMESTAMPTZ DEFAULT NOW(),
      updated_at            TIMESTAMPTZ DEFAULT NOW()
    );
  END IF;
END $$;

-- Patch influencer_id if table existed without it
ALTER TABLE public.content_approvals
  ADD COLUMN IF NOT EXISTS influencer_id         UUID REFERENCES public.influencers(id);

ALTER TABLE public.content_approvals
  ADD COLUMN IF NOT EXISTS coupon_id             UUID REFERENCES public.coupons(id),
  ADD COLUMN IF NOT EXISTS caption               TEXT,
  ADD COLUMN IF NOT EXISTS hashtags              TEXT[],
  ADD COLUMN IF NOT EXISTS media_url             TEXT,
  ADD COLUMN IF NOT EXISTS intended_posting_date TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_by           UUID,
  ADD COLUMN IF NOT EXISTS reviewed_at           TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS feedback              TEXT,
  ADD COLUMN IF NOT EXISTS auto_approved         BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS live_post_url         TEXT,
  ADD COLUMN IF NOT EXISTS posted_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS likes                 INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comments              INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shares                INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS submitted_at          TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS approval_expires_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_at            TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS updated_at            TIMESTAMPTZ DEFAULT NOW();

-- content_type (NOT NULL so handle separately)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'content_approvals' AND column_name = 'content_type'
  ) THEN
    ALTER TABLE public.content_approvals ADD COLUMN content_type TEXT;
  END IF;
END $$;

-- status on content_approvals — separate because of CHECK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'content_approvals' AND column_name = 'status'
  ) THEN
    ALTER TABLE public.content_approvals
      ADD COLUMN status TEXT DEFAULT 'pending'
        CHECK (status IN ('pending','approved','rejected','changes_requested','posted'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_content_influencer ON public.content_approvals(influencer_id);
CREATE INDEX IF NOT EXISTS idx_content_status     ON public.content_approvals(status);

-- ── 9. whatsapp_logs ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.whatsapp_logs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trigger         TEXT NOT NULL,
  recipient_phone TEXT NOT NULL,
  recipient_type  TEXT,
  influencer_id   UUID REFERENCES public.influencers(id),
  message         TEXT NOT NULL,
  status          TEXT DEFAULT 'sent' CHECK (status IN ('sent','delivered','failed')),
  error_message   TEXT,
  sent_at         TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_whatsapp_influencer ON public.whatsapp_logs(influencer_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_status     ON public.whatsapp_logs(status);

-- ── 10. Triggers ───────────────────────────────────────────
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
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
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

-- ── 11. Views ──────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_influencer_performance AS
SELECT
  i.id, i.name, i.email, i.instagram_handle, i.city, i.status,
  i.is_verified, i.discount_ceiling, i.total_orders, i.total_revenue,
  i.total_commission_earned, i.cod_rejection_rate,
  COUNT(DISTINCT c.id)  AS active_coupons,
  SUM(c.times_used)     AS total_coupon_uses,
  MAX(c.updated_at)     AS last_coupon_activity,
  i.created_at          AS joined_at,
  i.last_active_at
FROM public.influencers i
LEFT JOIN public.coupons c ON c.influencer_id = i.id AND c.status = 'active'
GROUP BY i.id;

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
