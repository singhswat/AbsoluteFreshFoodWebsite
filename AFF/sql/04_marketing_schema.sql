-- ═══════════════════════════════════════════════════════════
-- MARKETING & INFLUENCER MODULE SCHEMA
-- Absolute Fresh D2C Platform
-- ═══════════════════════════════════════════════════════════

-- ── CAMPAIGNS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('influencer', 'paid_ads', 'organic', 'sampling', 'referral', 'seasonal', 'society')),
  budget_allocated NUMERIC(10,2) DEFAULT 0,
  budget_spent NUMERIC(10,2) DEFAULT 0,
  revenue_generated NUMERIC(10,2) DEFAULT 0,
  valid_from DATE NOT NULL,
  valid_until DATE,
  utm_source TEXT,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'paused', 'completed')),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES public.users(id),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_campaigns_status ON public.campaigns(status);
CREATE INDEX idx_campaigns_dates ON public.campaigns(valid_from, valid_until);

-- ── INFLUENCERS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.influencers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT NOT NULL,
  password_hash TEXT, -- for direct login
  instagram_handle TEXT,
  youtube_url TEXT,
  facebook_url TEXT,
  follower_count INTEGER DEFAULT 0,
  content_category TEXT,
  city TEXT,
  address TEXT,
  pincode TEXT,
  
  -- Status & verification
  status TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('pending', 'approved', 'rejected', 'inactive')),
  is_verified BOOLEAN DEFAULT FALSE,
  verified_at TIMESTAMPTZ,
  
  -- Discount ceiling
  discount_ceiling NUMERIC(5,2) DEFAULT 25.00, -- max % they can set
  
  -- Performance tracking
  total_orders INTEGER DEFAULT 0,
  total_revenue NUMERIC(10,2) DEFAULT 0,
  total_commission_earned NUMERIC(10,2) DEFAULT 0,
  cod_rejection_count INTEGER DEFAULT 0,
  cod_rejection_rate NUMERIC(5,2) DEFAULT 0,
  
  -- Payment details
  bank_account TEXT,
  ifsc_code TEXT,
  upi_id TEXT,
  pan_number TEXT,
  
  -- Timestamps
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  last_active_at TIMESTAMPTZ,
  
  -- Agreement
  exclusivity_agreed_at TIMESTAMPTZ,
  
  -- Admin notes
  admin_notes TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_influencers_status ON public.influencers(status);
CREATE INDEX idx_influencers_email ON public.influencers(email);
CREATE INDEX idx_influencers_verified ON public.influencers(is_verified);
CREATE INDEX idx_influencers_city ON public.influencers(city);

-- ── COUPONS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  
  -- Relationships
  campaign_id UUID REFERENCES public.campaigns(id),
  influencer_id UUID REFERENCES public.influencers(id),
  
  -- Short link & QR
  short_link TEXT, -- af.in/priya20
  qr_code_url TEXT, -- URL to QR image
  
  -- Discount configuration
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'fixed_amount', 'free_delivery', 'product_specific')),
  discount_value NUMERIC(10,2) NOT NULL,
  product_id UUID REFERENCES public.products(id), -- for product_specific
  
  -- Constraints
  min_order_value NUMERIC(10,2) DEFAULT 0,
  max_discount_cap NUMERIC(10,2),
  
  -- Usage limits
  usage_limit_total INTEGER, -- null = unlimited
  usage_limit_per_customer INTEGER DEFAULT 1,
  times_used INTEGER DEFAULT 0,
  
  -- Validity
  valid_from TIMESTAMPTZ DEFAULT NOW(),
  expires_on TIMESTAMPTZ NOT NULL,
  
  -- Zone restriction
  applicable_zones TEXT[], -- array of pincodes
  
  -- Flags
  is_stackable BOOLEAN DEFAULT FALSE,
  first_order_only BOOLEAN DEFAULT FALSE,
  is_sample_coupon BOOLEAN DEFAULT FALSE,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'expired', 'depleted')),
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID, -- can be influencer_id or admin user_id
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_coupons_code ON public.coupons(UPPER(code));
CREATE INDEX idx_coupons_influencer ON public.coupons(influencer_id);
CREATE INDEX idx_coupons_campaign ON public.coupons(campaign_id);
CREATE INDEX idx_coupons_status ON public.coupons(status);
CREATE INDEX idx_coupons_expiry ON public.coupons(expires_on);

-- ── COUPON USAGE ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.coupon_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id UUID NOT NULL REFERENCES public.coupons(id),
  order_id UUID NOT NULL REFERENCES public.orders(id),
  
  -- Customer info
  customer_email TEXT,
  customer_phone TEXT,
  
  -- Financial tracking
  order_value NUMERIC(10,2) NOT NULL,
  discount_amount NUMERIC(10,2) NOT NULL,
  
  -- Attribution
  source TEXT, -- 'manual', 'short_link', 'qr_code'
  referrer_url TEXT,
  device_type TEXT,
  ip_address INET,
  
  used_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_coupon_usage_coupon ON public.coupon_usage(coupon_id);
CREATE INDEX idx_coupon_usage_order ON public.coupon_usage(order_id);
CREATE INDEX idx_coupon_usage_date ON public.coupon_usage(used_at);

-- ── INFLUENCER CLICKS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.influencer_clicks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id UUID NOT NULL REFERENCES public.coupons(id),
  influencer_id UUID NOT NULL REFERENCES public.influencers(id),
  
  -- Click metadata
  clicked_at TIMESTAMPTZ DEFAULT NOW(),
  referrer_url TEXT,
  device_type TEXT,
  ip_address INET,
  user_agent TEXT,
  
  -- Conversion tracking
  converted BOOLEAN DEFAULT FALSE,
  order_id UUID REFERENCES public.orders(id),
  converted_at TIMESTAMPTZ
);

CREATE INDEX idx_clicks_coupon ON public.influencer_clicks(coupon_id);
CREATE INDEX idx_clicks_influencer ON public.influencer_clicks(influencer_id);
CREATE INDEX idx_clicks_date ON public.influencer_clicks(clicked_at);
CREATE INDEX idx_clicks_converted ON public.influencer_clicks(converted);

-- ── COMMISSIONS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  influencer_id UUID NOT NULL REFERENCES public.influencers(id),
  
  -- Period
  month DATE NOT NULL, -- 1st of month
  
  -- Performance
  orders_delivered INTEGER DEFAULT 0,
  orders_rejected INTEGER DEFAULT 0,
  total_revenue NUMERIC(10,2) DEFAULT 0,
  
  -- Commission calculation
  tier TEXT CHECK (tier IN ('bronze', 'silver', 'gold')),
  rate_per_order NUMERIC(10,2),
  commission_amount NUMERIC(10,2) DEFAULT 0,
  tds_amount NUMERIC(10,2) DEFAULT 0,
  net_payout NUMERIC(10,2) DEFAULT 0,
  
  -- Payment
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'processing', 'paid', 'failed')),
  payment_method TEXT, -- 'upi', 'bank_transfer'
  payment_reference TEXT,
  paid_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(influencer_id, month)
);

CREATE INDEX idx_commissions_influencer ON public.commissions(influencer_id);
CREATE INDEX idx_commissions_month ON public.commissions(month);
CREATE INDEX idx_commissions_status ON public.commissions(payment_status);

-- ── SAMPLE REQUESTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sample_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  influencer_id UUID NOT NULL REFERENCES public.influencers(id),
  
  -- Request details
  product_id UUID NOT NULL REFERENCES public.products(id),
  quantity INTEGER DEFAULT 1,
  delivery_address TEXT NOT NULL,
  pincode TEXT,
  
  -- Content commitment
  content_type TEXT, -- 'instagram_post', 'story', 'reel', 'youtube'
  estimated_posting_date DATE,
  
  -- Approval
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'delivered', 'posted')),
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  
  -- Sample order
  sample_order_id UUID REFERENCES public.orders(id),
  sample_coupon_id UUID REFERENCES public.coupons(id), -- auto-generated follow-up coupon
  
  -- Fulfillment
  delivered_at TIMESTAMPTZ,
  
  -- Content posting
  post_url TEXT,
  posted_at TIMESTAMPTZ,
  
  -- Cost tracking
  sample_cost NUMERIC(10,2), -- product + packaging + delivery
  
  -- Timestamps
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_samples_influencer ON public.sample_requests(influencer_id);
CREATE INDEX idx_samples_status ON public.sample_requests(status);

-- ── CONTENT APPROVALS ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.content_approvals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  influencer_id UUID NOT NULL REFERENCES public.influencers(id),
  coupon_id UUID REFERENCES public.coupons(id),
  
  -- Content details
  content_type TEXT NOT NULL, -- 'instagram_post', 'story', 'reel', 'youtube'
  caption TEXT,
  hashtags TEXT[],
  media_url TEXT, -- uploaded draft image/video
  
  -- Posting plan
  intended_posting_date TIMESTAMPTZ,
  
  -- Review
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'changes_requested', 'posted')),
  reviewed_by UUID REFERENCES public.users(id),
  reviewed_at TIMESTAMPTZ,
  feedback TEXT,
  
  -- Auto-approval
  auto_approved BOOLEAN DEFAULT FALSE,
  
  -- Live post
  live_post_url TEXT,
  posted_at TIMESTAMPTZ,
  
  -- Engagement tracking
  likes INTEGER DEFAULT 0,
  comments INTEGER DEFAULT 0,
  shares INTEGER DEFAULT 0,
  
  -- Timestamps
  submitted_at TIMESTAMPTZ DEFAULT NOW(),
  approval_expires_at TIMESTAMPTZ, -- 7 days from approval
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_content_influencer ON public.content_approvals(influencer_id);
CREATE INDEX idx_content_status ON public.content_approvals(status);

-- ── WHATSAPP LOGS ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.whatsapp_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trigger TEXT NOT NULL, -- 'account_approved', 'coupon_assigned', 'first_order', etc.
  recipient_phone TEXT NOT NULL,
  recipient_type TEXT, -- 'influencer', 'admin'
  influencer_id UUID REFERENCES public.influencers(id),
  message TEXT NOT NULL,
  status TEXT DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'failed')),
  error_message TEXT,
  sent_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_whatsapp_influencer ON public.whatsapp_logs(influencer_id);
CREATE INDEX idx_whatsapp_status ON public.whatsapp_logs(status);

-- ══════════════════════════════════════════════════════════
-- EXTEND EXISTING TABLES
-- ══════════════════════════════════════════════════════════

-- Add coupon tracking to orders
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS coupon_id UUID REFERENCES public.coupons(id),
ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS customer_email TEXT,
ADD COLUMN IF NOT EXISTS customer_phone TEXT,
ADD COLUMN IF NOT EXISTS customer_name TEXT,
ADD COLUMN IF NOT EXISTS is_first_order BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_orders_coupon ON public.orders(coupon_id);

-- ══════════════════════════════════════════════════════════
-- FUNCTIONS & TRIGGERS
-- ══════════════════════════════════════════════════════════

-- Auto-increment coupon usage counter
CREATE OR REPLACE FUNCTION increment_coupon_usage()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.coupons
  SET times_used = times_used + 1,
      updated_at = NOW()
  WHERE id = NEW.coupon_id;
  
  -- Check if depleted
  UPDATE public.coupons
  SET status = 'depleted'
  WHERE id = NEW.coupon_id
    AND usage_limit_total IS NOT NULL
    AND times_used >= usage_limit_total;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_increment_coupon_usage ON public.coupon_usage;
CREATE TRIGGER trigger_increment_coupon_usage
AFTER INSERT ON public.coupon_usage
FOR EACH ROW
EXECUTE FUNCTION increment_coupon_usage();

-- Update influencer performance on order delivery
CREATE OR REPLACE FUNCTION update_influencer_performance()
RETURNS TRIGGER AS $$
DECLARE
  v_coupon_id UUID;
  v_influencer_id UUID;
  v_order_value NUMERIC;
BEGIN
  -- Only process if order status changed to 'delivered'
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    
    -- Get coupon and influencer
    v_coupon_id := NEW.coupon_id;
    
    IF v_coupon_id IS NOT NULL THEN
      SELECT influencer_id INTO v_influencer_id FROM public.coupons WHERE id = v_coupon_id;
      
      IF v_influencer_id IS NOT NULL THEN
        -- Calculate order value
        SELECT SUM(kg_ordered * unit_price) INTO v_order_value
        FROM public.order_items
        WHERE order_id = NEW.id;
        
        -- Update influencer stats
        UPDATE public.influencers
        SET total_orders = total_orders + 1,
            total_revenue = total_revenue + COALESCE(v_order_value, 0),
            last_active_at = NOW(),
            updated_at = NOW()
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
FOR EACH ROW
EXECUTE FUNCTION update_influencer_performance();

-- Auto-expire coupons
CREATE OR REPLACE FUNCTION expire_coupons()
RETURNS void AS $$
BEGIN
  UPDATE public.coupons
  SET status = 'expired',
      updated_at = NOW()
  WHERE status = 'active'
    AND expires_on < NOW();
END;
$$ LANGUAGE plpgsql;

-- ══════════════════════════════════════════════════════════
-- VIEWS FOR ANALYTICS
-- ══════════════════════════════════════════════════════════

-- Influencer performance summary
CREATE OR REPLACE VIEW public.v_influencer_performance AS
SELECT 
  i.id,
  i.name,
  i.email,
  i.instagram_handle,
  i.city,
  i.status,
  i.is_verified,
  i.discount_ceiling,
  i.total_orders,
  i.total_revenue,
  i.total_commission_earned,
  i.cod_rejection_rate,
  COUNT(DISTINCT c.id) as active_coupons,
  SUM(c.times_used) as total_coupon_uses,
  MAX(c.updated_at) as last_coupon_activity,
  i.created_at as joined_at,
  i.last_active_at
FROM public.influencers i
LEFT JOIN public.coupons c ON c.influencer_id = i.id AND c.status = 'active'
GROUP BY i.id;

-- Campaign ROI
CREATE OR REPLACE VIEW public.v_campaign_roi AS
SELECT 
  c.id,
  c.name,
  c.type,
  c.status,
  c.budget_allocated,
  c.budget_spent,
  c.revenue_generated,
  CASE 
    WHEN c.budget_spent > 0 
    THEN ROUND(((c.revenue_generated - c.budget_spent) / c.budget_spent * 100)::numeric, 2)
    ELSE 0 
  END as roi_percentage,
  COUNT(DISTINCT cp.id) as total_coupons,
  COUNT(DISTINCT cu.id) as total_redemptions,
  SUM(cu.discount_amount) as total_discounts_given,
  c.valid_from,
  c.valid_until
FROM public.campaigns c
LEFT JOIN public.coupons cp ON cp.campaign_id = c.id
LEFT JOIN public.coupon_usage cu ON cu.coupon_id = cp.id
GROUP BY c.id;

COMMENT ON TABLE public.campaigns IS 'Marketing campaigns for organizing coupons and tracking ROI';
COMMENT ON TABLE public.influencers IS 'Influencer partners who promote products via coupons';
COMMENT ON TABLE public.coupons IS 'Discount coupons created by influencers or admins';
COMMENT ON TABLE public.coupon_usage IS 'Tracks every coupon redemption with attribution';
COMMENT ON TABLE public.influencer_clicks IS 'Tracks short link and QR code clicks';
COMMENT ON TABLE public.commissions IS 'Monthly commission calculations for influencers';
