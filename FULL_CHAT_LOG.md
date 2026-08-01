# Absolute Fresh — Full Development Chat Log
**Project:** AFF D2C Sales + Marketing Platform  
**Stack:** Vanilla HTML/JS · Supabase (PostgreSQL) · Hostinger  
**Supabase Project:** `fbfopgzblqmsflkfejwa.supabase.co`  
**Supabase Anon Key:** `sb_publishable_r7mYhsyIKtBjBKzxH8St9g_OHjTU-RQ`

---

## What Was Asked & Built (Full Summary)

### Initial Request
User uploaded `AbsoluteFreshFood_Marketing_Strategy_WorldClass_v1_FINAL.docx` and asked to implement Phase 2 marketing features, make the website ready, and set up Supabase schema/RLS properly.

---

## Phase 1 — Marketing Module (Already Built Before This Chat)

| Feature | File | Notes |
|---|---|---|
| Influencer self-signup | `AFF/marketing/signup.html` | Auto-approved, instant access |
| Partner login | `AFF/marketing/login.html` | SHA-256 password hash |
| Dashboard — Coupons tab | `AFF/marketing/dashboard.html` | Create, pause, QR, WhatsApp share |
| Dashboard — Performance | `AFF/marketing/dashboard.html` | Clicks, CVR per coupon |
| Admin panel | `AFF/marketing/admin.html` | Influencer mgmt, ceiling adjust |
| Base SQL schema | `AFF/sql/04_marketing_schema.sql` | 10 tables + triggers |

---

## Phase 2 — Full Platform (Built This Chat)

### `AFF/marketing/dashboard.html` — 4 new tabs added

**Coupons tab** (enhanced)
- Per-coupon click counts and CVR from `influencer_clicks`
- WhatsApp share button, pause/resume

**Samples tab** (new)
- Request free product samples (`sample_requests` table)
- Product picker with string keys (`idli-batter`, `dosa-batter`, etc.)
- Status pipeline: Pending → Approved → Delivered → Posted
- Mark-as-posted with live URL

**Content tab** (new)
- Submit caption/hashtags/draft link to `content_approvals`
- Linked to coupon
- View approval feedback, mark live URL

**Earnings tab** (new)
- Tier progress bar (Bronze/Silver/Gold)
- Estimated commission
- Payment history from `commissions`
- Save UPI/bank/PAN to `influencers`

### `AFF/marketing/admin.html` — 5 new tabs (7 total)

| Tab | Features |
|---|---|
| Influencers | Filter by tier, verify/unverify, edit ceiling |
| Coupons | Pause/resume/expire |
| **Campaigns** | Full CRUD via modal, filter by status, budget/UTM/notes |
| **Samples** | Approve/reject with reason, mark delivered |
| **Content Reviews** | Approve/reject/request-changes with mandatory feedback |
| **Payouts** | Client-side TDS calc (10% if `pan_number` present), mark paid with UTR |
| **Analytics** | Revenue attribution per influencer, campaign ROI, top coupons |

### `AFF/sql/05_marketing_phase2.sql` (new file)
- RLS policies (`ENABLE ROW LEVEL SECURITY` + policies) on all 9 marketing tables
- `calculate_tds()` BEFORE INSERT OR UPDATE trigger on `commissions`
- `log_whatsapp_notification()` helper function
- `auto_calculate_monthly_commissions()` for pg_cron
- Views: `v_influencer_leaderboard`, `v_marketing_summary`

---

## SQL Schema Debugging (The Hard Part)

### The Error
```
ERROR: 42703: column "influencer_id" does not exist
```
This error persisted across **4 fix attempts**. Here's what happened each time:

### Fix v1
Created `04b_marketing_schema_fix.sql` with `ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS influencer_id`. Failed because the same statement also referenced `campaigns` table which didn't exist yet — entire `ALTER TABLE` rolled back atomically.

### Fix v2
Rewrote with strict dependency order. Still failed — same root cause in a different column.

### Fix v3
Used `DO $$` blocks to guard `sample_requests` and `content_approvals`. Still failed.

### Production Diagnostic (the breakthrough)
Ran a 5-part diagnostic query:
```sql
-- Tables, columns, views, triggers, foreign keys
SELECT table_name, column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('coupons','influencers','campaigns','orders',...)
ORDER BY table_name, ordinal_position;
```

**Findings:**

| Table | Missing Columns |
|---|---|
| `coupons` | `campaign_id`, `qr_code_url`, `max_discount_cap`, `applicable_zones`, `is_sample_coupon`, `product_id` |
| `orders` | `customer_email`, `customer_phone`, `customer_name`, `is_first_order` |
| `whatsapp_logs` | Has `recipient` (wrong name), missing `recipient_type`, `influencer_id`, `error_message` |
| Everything else | ✅ Complete |

**Root cause confirmed:** Earlier fix scripts had `ADD COLUMN ... product_id UUID REFERENCES public.products(id)` inline in the main `ALTER TABLE coupons`. Even though `products` table exists in production, if it wasn't found during some earlier run, the entire statement rolled back. Views referencing `coupons.campaign_id` then failed with the misleading "influencer_id does not exist" error.

**Additional finding:** `orders.status` is a custom enum type `order_status`, not plain `TEXT`. This caused the `update_influencer_performance` trigger to fail silently when comparing status strings.

### Fix v4 — `04c_exact_gap_fix.sql` ✅ SUCCESSFUL
Minimal targeted script:
```sql
-- coupons: 6 missing columns (campaigns + products both confirmed to exist)
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS campaign_id      UUID REFERENCES public.campaigns(id),
  ADD COLUMN IF NOT EXISTS qr_code_url      TEXT,
  ADD COLUMN IF NOT EXISTS max_discount_cap NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS applicable_zones TEXT[],
  ADD COLUMN IF NOT EXISTS is_sample_coupon BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS product_id       UUID REFERENCES public.products(id);

-- orders: 4 missing columns
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS customer_email TEXT,
  ADD COLUMN IF NOT EXISTS customer_phone TEXT,
  ADD COLUMN IF NOT EXISTS customer_name  TEXT,
  ADD COLUMN IF NOT EXISTS is_first_order BOOLEAN DEFAULT FALSE;

-- whatsapp_logs: rename recipient → recipient_phone + add 3 columns
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='whatsapp_logs' AND column_name='recipient')
  THEN ALTER TABLE public.whatsapp_logs RENAME COLUMN recipient TO recipient_phone;
  END IF;
END $$;
ALTER TABLE public.whatsapp_logs
  ADD COLUMN IF NOT EXISTS recipient_type TEXT,
  ADD COLUMN IF NOT EXISTS influencer_id  UUID REFERENCES public.influencers(id),
  ADD COLUMN IF NOT EXISTS error_message  TEXT;

-- Trigger fix: cast orders.status to TEXT (it's a custom enum)
-- update_influencer_performance now uses NEW.status::TEXT = 'delivered'

-- Views recreated: v_influencer_performance, v_campaign_roi
```

---

## Commission Structure

| Tier | Orders/month | Rate |
|---|---|---|
| 🥉 Bronze | 1–10 | ₹30 / delivered order |
| 🥈 Silver | 11–30 | ₹50 / delivered order |
| 🥇 Gold | 31+ | ₹75 / delivered order |

**TDS:** 10% deducted if `pan_number` is on file AND annual payout exceeds ₹30,000.

---

## Web Orders System

### Problem
Orders went only to WhatsApp chat — easy to miss, no history, impossible to track.

### Solution
Orders save to Supabase first. WhatsApp is a notification ping, not the system of record.

### `06_web_orders.sql`

```sql
CREATE TABLE public.web_orders (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_ref        TEXT UNIQUE DEFAULT 'WO-' || nextval('web_order_seq'),
  customer_name    TEXT NOT NULL,
  customer_phone   TEXT NOT NULL,
  customer_address TEXT NOT NULL,
  items            JSONB NOT NULL DEFAULT '[]',
  coupon_code      TEXT,
  coupon_id        UUID REFERENCES public.coupons(id),
  subtotal         NUMERIC(10,2),
  discount_amount  NUMERIC(10,2),
  total            NUMERIC(10,2),
  status           TEXT DEFAULT 'new'
    CHECK (status IN ('new','confirmed','locked','out_for_delivery','delivered','cancelled')),
  delivery_date    DATE,
  delivery_slot    TEXT,
  admin_notes      TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);
```

`items` JSONB structure:
```json
[{"name":"1 kg Pack","qty":2,"price":135,"total":270}]
```

**Cutoff logic:**
- Stored in `app_settings` table, key = `order_cutoff_time`, value = `20:00`
- Also cached in `localStorage` key `aff_cutoff_hour` for the website
- `lock_past_cutoff_orders()` function can be called via pg_cron at 8pm daily

### Order Status Pipeline
```
new → confirmed → out_for_delivery → delivered
                                    cancelled (from new or confirmed only)
                                    locked (after 8pm cutoff)
```

### Website (`index.html`) — Updated Flow
1. Customer picks packs + quantities
2. Clicks **Place Order**
3. JS saves to `web_orders` via Supabase → gets back `order_ref`
4. Form hides, success screen shows with order ref badge
5. WhatsApp button opens `wa.me/919123456789` with pre-filled ping: *"I just placed Order WO-1042 — please confirm my slot"*
6. "Place another order" button resets the form

### Admin (`admin.html → 🛒 Web Orders` tab)
- Stats bar: New / Confirmed / Out for Delivery / Delivered today
- Date filter: Today / Yesterday / All
- Order table with one-click pipeline advancement
- Edit modal: name, phone, address, delivery date, status, admin notes
- Cutoff time picker at top of tab (saves to localStorage + Supabase)

---

## Order Form Redesign (`Website Absolute Fresh/index.html`)

**Before:** Flat `<select>` dropdown, single pack, no quantity, no total.

**After:**
- 4 visual product cards (2×2 grid) with emoji, description, price, and `− qty +` stepper
- Subscription toggles (Daily / Weekly) as pill buttons
- Live order summary that appears on first selection
- Coupon discount updates instantly in summary when applied
- WhatsApp message now sends full itemised order

---

## Influencer Partner Section (Homepage)

Three touchpoints added to `Website Absolute Fresh/index.html`:

### 1. Nav link
```html
<li><a href="#partners">Partner With Us</a></li>
```

### 2. New `#partners` section (before footer)
Dark green section matching site aesthetic:
- Three cards: ₹30–₹75 commission / Free samples / Real-time dashboard
- CTA → `/dev/marketing/signup.html`
- Secondary link for existing partners → `/dev/marketing/login.html`

### 3. Footer column
New **Partners** column: Partner Program · Apply Now · Partner Login

---

## Google Analytics

**ID:** `G-FL4T5WHM8W`

Added to `<head>` (first element) on all HTML files:

| Project | Files |
|---|---|
| `Website Absolute Fresh` | `index.html` |
| `AFF_SalesApp_v48_Marketing` | `index.html`, `signup.html`, `login.html`, `dashboard.html`, `admin.html`, `forgot-password.html`, `reset-password.html` |
| `AFF_SalesApp_v47` | `index.html` + 14 pages in `/pages/` (updated via Python script) |

---

## All Files — What's Where

### SQL Files (run in Supabase SQL Editor)
| File | Purpose | Status |
|---|---|---|
| `AFF/sql/04_marketing_schema.sql` | Original base schema | Existing |
| `AFF/sql/04b_marketing_schema_fix.sql` | Earlier fix attempts | Superseded |
| `AFF/sql/04c_exact_gap_fix.sql` | **THE fix — run this** | ✅ Run & confirmed |
| `AFF/sql/05_marketing_phase2.sql` | RLS + Phase 2 functions | Run after 04c |
| `AFF/sql/06_web_orders.sql` | Web orders table | Run after 05 |

### Marketing Portal (`AFF/marketing/`)
| File | Purpose |
|---|---|
| `signup.html` | Influencer self-registration |
| `login.html` | Influencer login |
| `dashboard.html` | Influencer dashboard (4 tabs) |
| `admin.html` | Admin panel (8 tabs incl. Web Orders) |
| `forgot-password.html` | Password reset request |
| `reset-password.html` | Password reset confirm |

### Website
| File | Purpose |
|---|---|
| `Website Absolute Fresh/index.html` | Main website — order form, partner section |

---

## Deployment Checklist

### Supabase
- [x] `04c_exact_gap_fix.sql` — confirmed successful
- [ ] `05_marketing_phase2.sql`
- [ ] `06_web_orders.sql`
- [ ] Enable pg_cron extension in Dashboard → Database → Extensions
- [ ] Run cron schedules:
  ```sql
  SELECT cron.schedule('expire-coupons-daily', '0 0 * * *', $$SELECT expire_coupons()$$);
  SELECT cron.schedule('monthly-commissions', '0 1 1 * *', $$SELECT auto_calculate_monthly_commissions()$$);
  SELECT cron.schedule('lock-orders-cutoff', '0 20 * * *', $$SELECT lock_past_cutoff_orders()$$);
  ```

### Hostinger Upload
- [ ] `Website Absolute Fresh/index.html` → `public_html/index.html`
- [ ] `AFF/marketing/` → `public_html/dev/marketing/`

### Before Going Live
- [ ] Change admin PIN in `admin.html` (currently `123456789`)
- [ ] Update WhatsApp number in `index.html` (currently `919123456789` placeholder)
- [ ] Test order flow: place order → check Supabase web_orders table → verify WA ping opens
- [ ] Set production cutoff time from Admin → Web Orders tab
- [ ] Move influencer login to Supabase Edge Function (avoid password_hash via anon key)
- [ ] Enable column-level security on `bank_account`, `pan_number`
- [ ] Store Interakt API key in Supabase Vault when ready

---

## Architecture Overview

```
Customer (website → absolutefreshfood.com)
  └─ Picks packs + qty → Place Order
     └─ Saved to web_orders (Supabase)
     └─ WhatsApp ping to business (customer opens wa.me)

Admin (admin.html → PIN protected)
  └─ Web Orders tab → queue of new orders
     └─ Confirm → Out for Delivery → Delivered
     └─ Edit order if customer requests change
     └─ Cutoff 8pm → orders lock for overnight grinding

Influencer (marketing portal → /dev/marketing/)
  └─ signup.html → creates row in influencers table
  └─ login.html → SHA-256 hash check
  └─ dashboard.html
     ├─ Coupons → create code → share QR + WhatsApp
     ├─ Samples → request free products
     ├─ Content → submit for approval before posting
     └─ Earnings → view commissions + save payment details

Website order uses coupon code
  └─ coupon_usage row created
  └─ influencer_clicks tracked
  └─ trigger updates influencers.total_orders + total_revenue
  └─ monthly pg_cron calculates commissions automatically
```

---

## Key Technical Decisions

| Decision | Reason |
|---|---|
| `web_orders` separate from `orders` | `orders` requires `outlet_id NOT NULL` + `rep_id NOT NULL` — web customers have neither. Separate table avoids FK hacks. |
| WhatsApp as ping, not record | Without Interakt API, business can't push messages to customers. Customer-initiated `wa.me` is the practical startup option. |
| Cutoff in both localStorage + app_settings | localStorage = instant reads on website without extra DB call. app_settings = admin control + cross-device sync. |
| `reviewed_by` as plain UUID (no FK to users) | Avoids dependency on `users` table existing in marketing-only deployments. |
| `orders.status::TEXT` cast in trigger | Column is custom enum `order_status`, not plain text — direct string comparison fails silently. |
| product_id on coupons in separate DO block | Inline `REFERENCES public.products(id)` in a multi-column ALTER TABLE will roll back ALL columns if products doesn't exist at run time. |
| Interakt deferred | Startup stage — manual WhatsApp Business is sufficient. Interakt adds value when volume justifies template approval overhead. |

---

## Pending / Phase 3

- [ ] WhatsApp Edge Function — call Interakt API from Supabase on key events (order confirmed, commission paid, coupon expired)
- [ ] Supabase Auth migration — replace SHA-256 custom hash with proper Supabase Auth
- [ ] Short link service — `af.in` domain with redirect + click tracking
- [ ] Razorpay payouts — automated commission transfers
- [ ] Content media upload — Supabase Storage for draft images/videos
- [ ] Web order customer portal — let customers check order status by phone number without WhatsApp
