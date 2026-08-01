# Absolute Fresh — Dev Session Log
**Date:** 22 May 2026  
**Scope:** Marketing module fixes, web order capture, Google Analytics, influencer signup on homepage

---

## 1. SQL Schema Fixes

### Problem
The Supabase schema was failing with `ERROR: 42703: column "influencer_id" does not exist` every time we tried to run the marketing schema scripts. After three failed fix attempts, we ran a full production diagnostic to understand the actual state of the database.

### Root Cause
The `ALTER TABLE public.coupons` statement in earlier fix scripts included `ADD COLUMN ... product_id UUID REFERENCES public.products(id)`. When the `products` table didn't exist at that moment, the entire `ALTER TABLE` rolled back atomically — including the `influencer_id` addition — leaving the column missing. Views referencing `coupons.influencer_id` then failed at creation time.

### Production Diagnostic
Ran a 5-part diagnostic query covering all tables, columns, views, triggers, and foreign keys. Key findings:

| Table | Status |
|---|---|
| `campaigns` | ✅ Complete |
| `commissions` | ✅ Complete |
| `content_approvals` | ✅ Complete |
| `coupon_usage` | ✅ Complete |
| `coupons` | ⚠️ Missing 6 columns |
| `influencer_clicks` | ✅ Complete |
| `influencers` | ✅ Complete |
| `orders` | ⚠️ Missing 4 columns |
| `sample_requests` | ✅ Complete |
| `whatsapp_logs` | ⚠️ `recipient` column misnamed, missing 3 columns |

### Fix: `04c_exact_gap_fix.sql`
Targeted script adding only confirmed-missing columns:

**`coupons`** — added: `campaign_id`, `qr_code_url`, `max_discount_cap`, `applicable_zones`, `is_sample_coupon`, `product_id`

**`orders`** — added: `customer_email`, `customer_phone`, `customer_name`, `is_first_order`

**`whatsapp_logs`** — renamed `recipient` → `recipient_phone` via DO block (safe to re-run), added `recipient_type`, `influencer_id`, `error_message`

Also recreated all triggers and views (`v_influencer_performance`, `v_campaign_roi`). The `update_influencer_performance` trigger was updated to cast `orders.status` to TEXT before comparing (it's a custom enum `order_status` type, not plain text).

**Status: ✅ Ran successfully in production**

---

## 2. Phase 2 RLS + Functions

**File:** `AFF/sql/05_marketing_phase2.sql`

Run after `04c_exact_gap_fix.sql`. Adds:
- Row Level Security on all 9 marketing tables
- `calculate_tds()` trigger on `commissions` (10% TDS if PAN + >₹30k annual payout)
- `auto_calculate_monthly_commissions()` function for pg_cron
- `log_whatsapp_notification()` helper
- Views: `v_influencer_leaderboard`, `v_marketing_summary`

**pg_cron schedules** (run after enabling pg_cron extension in Supabase):
```sql
SELECT cron.schedule('expire-coupons-daily', '0 0 * * *', $$SELECT expire_coupons()$$);
SELECT cron.schedule('monthly-commissions', '0 1 1 * *', $$SELECT auto_calculate_monthly_commissions()$$);
```
> Note: pg_cron schema must exist before running. Enable the extension in Supabase Dashboard → Database → Extensions first.

---

## 3. Web Orders System

### Problem
Orders placed on the website went only to WhatsApp chat — easy to miss, no history, impossible to track at scale.

### Solution
Orders now save to Supabase first. WhatsApp becomes a notification ping, not the system of record.

### SQL: `06_web_orders.sql`

```
web_orders table:
  id, order_ref (WO-1000, WO-1001…), customer_name, customer_phone,
  customer_address, items (JSONB), coupon_code, coupon_id,
  subtotal, discount_amount, total,
  status: new → confirmed → locked → out_for_delivery → delivered → cancelled
  delivery_date, delivery_slot, admin_notes, created_at, updated_at
```

- `order_ref` auto-generates from a sequence (`WO-1000`, `WO-1001`, …)
- `lock_past_cutoff_orders()` function locks `new`/`confirmed` orders past the cutoff time
- RLS: public INSERT (website form), public SELECT/UPDATE for edits before cutoff
- Cutoff time stored in `app_settings` table under key `order_cutoff_time` (default `20:00`)

### Order Cutoff Logic
- Orders placed **before 8pm** → delivery tomorrow
- Orders placed **after 8pm** → delivery day after tomorrow (grinding has started)
- Cutoff is adjustable from the Admin → Web Orders tab at any time
- Value stored in both `localStorage` (website) and `app_settings` (Supabase)

### Website Flow (`index.html`)
1. Customer selects packs + quantities, enters name/phone/address
2. Clicks **Place Order**
3. JS saves to `web_orders` via Supabase client
4. Success screen shows order ref (e.g. `WO-1042`)
5. WhatsApp button opens `wa.me` with pre-filled ping: *"I just placed Order WO-1042 — please confirm my slot"*
6. Customer can click "Place another order" to reset the form

### Admin Tab (`admin.html → 🛒 Web Orders`)
- **Stats bar**: New / Confirmed / Out for Delivery / Delivered today
- **Date filter**: Today / Yesterday / All
- **Order table**: Ref, time, customer name, phone, items, total, status, actions
- **Actions per order**: Confirm → Out for Delivery → Mark Delivered (one-click pipeline), Edit, Cancel
- **Edit modal**: Change name, phone, address, delivery date, status, add admin notes
- **Cutoff time setting**: Time picker at top of tab, saves to localStorage + Supabase

---

## 4. Order Form Redesign (`Website Absolute Fresh/index.html`)

Replaced the flat `<select>` dropdown with a visual pack picker:

- **4 product cards** in a 2×2 grid: 1kg Pack (₹135), 500g Pack (₹75), 200g Trial (₹35), Bulk/B2B (custom)
- Each card has a `−  qty  +` stepper
- **Subscription toggles**: Daily / Weekly as pill buttons
- **Live order summary** — appears when any pack is selected, shows itemised total with coupon discount
- Coupon discount updates live in the summary when applied

---

## 5. Influencer Partner Section (`Website Absolute Fresh/index.html`)

Added three touchpoints for influencer discovery on the homepage:

### Nav bar
Added `Partner With Us` link between FAQs and Reserve Fresh Batch CTA.

### New Section (`#partners`)
Dark green section (matching ingredients section style) placed before the footer:
- Three benefit cards: ₹30–₹75 per delivered order / Free samples for content / Real-time dashboard
- **"Apply to become a Partner"** button → `/dev/marketing/signup.html`
- Secondary link: *"Already a partner? Log in →"*

### Footer
New **Partners** column with: Partner Program, Apply Now, Partner Login links.

---

## 6. Google Analytics

**Tracking ID:** `G-FL4T5WHM8W`

Added to all HTML files across all three projects:

| Project | Files Updated |
|---|---|
| `Website Absolute Fresh` | `index.html` |
| `AFF_SalesApp_v48_Marketing` | `index.html`, `signup.html`, `login.html`, `dashboard.html`, `admin.html`, `forgot-password.html`, `reset-password.html` |
| `AFF_SalesApp_v47` | `index.html` + all 14 pages in `/pages/` |

Snippet placed as the **first element inside `<head>`** on every page (Google's recommended position for accurate pageview tracking).

---

## 7. Files Changed This Session

### New Files
| File | Purpose |
|---|---|
| `AFF/sql/04c_exact_gap_fix.sql` | Targeted production schema fix (run this) |
| `AFF/sql/06_web_orders.sql` | Web orders table, RLS, cutoff function |

### Modified Files
| File | Changes |
|---|---|
| `Website Absolute Fresh/index.html` | GA snippet, pack picker UI, order form → Supabase, partner section |
| `AFF/marketing/admin.html` | GA snippet, Web Orders tab + modal |
| `AFF_SalesApp_v47/AFF/index.html` + all pages | GA snippet |

### Existing Files (reference, not changed this session)
| File | Purpose |
|---|---|
| `AFF/sql/04_marketing_schema.sql` | Original base schema |
| `AFF/sql/04b_marketing_schema_fix.sql` | Earlier fix attempts (superseded by 04c) |
| `AFF/sql/05_marketing_phase2.sql` | RLS + Phase 2 functions |
| `AFF/marketing/dashboard.html` | Influencer dashboard (Coupons, Samples, Content, Earnings tabs) |
| `AFF/MARKETING_DEPLOYMENT.md` | Full deployment guide |

---

## 8. Deployment Checklist

### Supabase (run in SQL Editor, in order)
- [x] `04c_exact_gap_fix.sql` — confirmed successful
- [ ] `05_marketing_phase2.sql` — RLS + Phase 2 functions
- [ ] `06_web_orders.sql` — web orders table
- [ ] Enable pg_cron extension → run the two cron schedule lines

### Hostinger Upload
- [ ] `Website Absolute Fresh/index.html` → `public_html/index.html`
- [ ] `AFF/marketing/` folder → `public_html/dev/marketing/`

### Before Production
- [ ] Change admin PIN in `admin.html` (currently `123456789`)
- [ ] Update WhatsApp number in `index.html` (currently placeholder `919123456789`)
- [ ] Test full order flow: place order → check Supabase → verify WA ping
- [ ] Set production cutoff time from Admin → Web Orders tab

---

## 9. Architecture Summary

```
Customer (website)
  └─ Places order → Supabase web_orders table
                  └─ WhatsApp ping to business (customer-initiated)

Admin (admin.html)
  └─ Web Orders tab → view queue → confirm → dispatch → deliver
  └─ Cutoff time setting → locks orders at 8pm (adjustable)

Influencer (marketing portal)
  └─ signup.html → login.html → dashboard.html
  └─ Coupons → Samples → Content → Earnings
  └─ Coupon codes used on website → tracked in coupon_usage table
  └─ Commissions calculated monthly (auto via pg_cron)
```

---

## 10. Key Decisions & Rationale

| Decision | Rationale |
|---|---|
| `web_orders` separate from `orders` | `orders` table requires `outlet_id` + `rep_id` (NOT NULL); web customers don't have outlets. Separate table avoids FK hacks. |
| WhatsApp as ping, not system of record | Without Interakt API, the business can't push messages to customers. Customer-initiated `wa.me` link is the realistic option for a startup. |
| Cutoff stored in both localStorage and app_settings | localStorage for instant website reads without an extra DB call; app_settings for admin control and cross-device consistency. |
| `reviewed_by` as plain UUID (no FK to users) | Avoids dependency on the `users` table existing in all environments. |
| `orders.status` cast to TEXT in trigger | The column is a custom enum `order_status`, not plain text — direct string comparison would fail silently. |
