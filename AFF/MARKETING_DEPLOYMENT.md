# Marketing Module — Deployment Guide (Phase 1 + 2)

## What's Built

### ✅ Phase 1 — MVP (Complete)
| Feature | File | Notes |
|---|---|---|
| Influencer self-signup | `signup.html` | Auto-approved, instant access |
| Partner login | `login.html` | SHA-256 password hash |
| Dashboard — Coupons tab | `dashboard.html` | Create, pause, QR, WhatsApp share |
| Dashboard — Performance | `dashboard.html` | Clicks, CVR per coupon |
| Admin panel | `admin.html` | Influencer mgmt, ceiling adjust |
| Coupon management | `admin.html` | Pause/resume/expire coupons |
| SQL schema | `sql/04_marketing_schema.sql` | 10 tables + triggers |

### ✅ Phase 2 — Full Platform (Complete)
| Feature | File | Notes |
|---|---|---|
| Sample request system | `dashboard.html` → Samples tab | Request → Approve → Deliver → Post |
| Content approval workflow | `dashboard.html` → Content tab | Submit → Review → Approve → Go Live |
| Campaign management | `admin.html` → Campaigns tab | Create, track ROI, UTM |
| Commission payouts | `admin.html` → Payouts tab | Recalculate, TDS, mark paid |
| Content review queue | `admin.html` → Content tab | Approve/reject/request changes |
| Sample request queue | `admin.html` → Samples tab | Approve/reject/mark delivered |
| Advanced analytics | `admin.html` → Analytics tab | Attribution, campaign ROI, top coupons |
| WhatsApp share | `dashboard.html` | wa.me deep links from QR modal |
| Payment details | `dashboard.html` → Earnings tab | UPI, bank, PAN for TDS |
| TDS calculation | `sql/05_marketing_phase2.sql` | 10% TDS if PAN + >₹30k annual |
| RLS policies | `sql/05_marketing_phase2.sql` | Row-level security on all tables |
| Monthly auto-commission | `sql/05_marketing_phase2.sql` | pg_cron function (enable in Supabase) |

---

## Deployment Steps

### Step 1: Deploy SQL Schema

```bash
# In Supabase SQL Editor → run in order:
# 1. sql/04_marketing_schema.sql  (base tables, triggers)
# 2. sql/05_marketing_phase2.sql  (RLS, TDS trigger, views, pg_cron setup)
```

### Step 2: Enable Supabase Extensions

In Supabase Dashboard → Database → Extensions:
- ✅ Enable **pg_cron** (for daily coupon expiry + monthly commission calc)

Then run in SQL Editor:
```sql
-- Expire coupons daily at midnight
SELECT cron.schedule('expire-coupons-daily', '0 0 * * *', $$SELECT expire_coupons()$$);

-- Calculate commissions on 1st of month at 1am
SELECT cron.schedule('monthly-commissions', '0 1 1 * *', $$SELECT auto_calculate_monthly_commissions()$$);
```

### Step 3: Upload to Hostinger

Upload `AFF/marketing/` folder to:
```
public_html/dev/marketing/
  signup.html
  login.html
  dashboard.html
  admin.html
  forgot-password.html
  reset-password.html
  README.md
```

### Step 4: WhatsApp Integration (Interakt)

1. Log in to [app.interakt.ai](https://app.interakt.ai)
2. Create message templates for:
   - `account_approved` — Welcome new influencer
   - `first_order` — First order milestone
   - `coupon_expired` — Coupon expiry reminder
   - `commission_paid` — Payment confirmation
3. Store API key in Supabase Vault:
   ```sql
   SELECT vault.create_secret('interakt_api_key', 'your-api-key-here');
   ```
4. Create Edge Function `send-whatsapp` that calls Interakt API + logs to `whatsapp_logs` table

### Step 5: Test the Full Flow

**Influencer Registration:**
1. Visit `/marketing/signup.html` → fill form → auto-approved
2. Login at `/marketing/login.html`
3. Create coupon: `PRIYA20`, 20% off, 30 days
4. QR code → WhatsApp share → `wa.me` opens with pre-filled text
5. Request sample → choose product + address → submit

**Admin Review:**
1. Visit `/marketing/admin.html` → PIN: `123456789`
2. **Influencers tab** → verify influencer → adjust ceiling
3. **Samples tab** → approve Priya's sample request → mark delivered
4. **Content tab** → review submitted content → approve
5. **Campaigns tab** → create "Summer Launch" campaign
6. **Payouts tab** → click Recalculate → mark commissions paid with UTR

**Analytics Check:**
1. Admin → Analytics tab
2. Revenue attribution shows per-influencer ROI
3. Top coupons table shows usage

---

## Supabase Schema Overview

```
campaigns          → Marketing campaigns (ROI tracking)
influencers        → Partner profiles (status, ceiling, payment details)
coupons            → Discount codes (linked to campaigns + influencers)
coupon_usage       → Every redemption with attribution
influencer_clicks  → Short link / QR click tracking
commissions        → Monthly payout records (with TDS)
sample_requests    → Free product sample pipeline
content_approvals  → Content review workflow
whatsapp_logs      → Notification audit trail
```

### Key Views
| View | Purpose |
|---|---|
| `v_influencer_leaderboard` | Ranked list with tier + pending items |
| `v_influencer_performance` | Performance summary per influencer |
| `v_campaign_roi` | Campaign-level ROI analytics |
| `v_marketing_summary` | Single-row admin dashboard summary |

---

## Commission Structure

| Tier | Threshold | Rate |
|---|---|---|
| 🥉 Bronze | 1–10 orders | ₹30 / delivered order |
| 🥈 Silver | 11–30 orders | ₹50 / delivered order |
| 🥇 Gold | 31+ orders | ₹75 / delivered order |

**TDS deduction:** 10% if PAN on file AND annual payout exceeds ₹30,000

---

## Admin PIN

Change `ADMIN_PIN` at top of `admin.html` before production deployment.
Default: `123456789` ← **CHANGE THIS**

Production recommendation: Replace PIN auth with Supabase Auth (email + OTP for admin users).

---

## Phase 2 → Phase 3 Roadmap

### Immediate (Deploy Now)
- [x] Sample request system
- [x] Content approval workflow  
- [x] Campaign management
- [x] Commission payouts + TDS
- [x] Advanced analytics

### Next Sprint (Phase 3)
- [ ] **WhatsApp Edge Function** — call Interakt API from Supabase on key events
- [ ] **Supabase Auth migration** — replace custom password hash with proper auth
- [ ] **Short link service** — set up `af.in` with redirect + click tracking
- [ ] **Razorpay payouts** — automated commission transfers
- [ ] **Content media upload** — Supabase Storage for draft images/videos
- [ ] **Push notifications** — web push for influencer milestone alerts

### Stretch Goals
- [ ] Referral-of-influencer program (influencers recruit sub-influencers)
- [ ] Society campaign management (bulk coupon codes per apartment complex)
- [ ] Paid ads ROI tracker (sync Google/Meta Ads spend)
- [ ] Mobile app (React Native wrapper of the dashboard)

---

## URLs (After Deployment)

| Page | URL | Access |
|---|---|---|
| Signup | `/marketing/signup.html` | Public |
| Login | `/marketing/login.html` | Public |
| Influencer Dashboard | `/marketing/dashboard.html` | Protected (localStorage token) |
| Admin Panel | `/marketing/admin.html` | Protected (PIN) |

---

## Security Checklist (Before Production)

- [ ] Change admin PIN in `admin.html`
- [ ] Move influencer login to Supabase Edge Function (avoid password_hash exposure)
- [ ] Enable Supabase Auth for admin users
- [ ] Add column-level security on `bank_account`, `pan_number`, `password_hash`
- [ ] Store Interakt API key in Supabase Vault (not hardcoded)
- [ ] Enable PITR (Point-in-Time Recovery) on the database
- [ ] Set up Supabase email confirmations for new signups
- [ ] Rate-limit the signup endpoint (Supabase rate limiting)
