# Marketing & Influencer Module

Self-service influencer marketing platform for Absolute Fresh D2C sales.

## Features Built (Phase 1 - MVP)

### Influencer Features
- ✅ Self-registration (auto-approved)
- ✅ Login & dashboard
- ✅ Create custom coupons with discount ceiling validation
- ✅ QR code generation for offline promotion
- ✅ Short link system (af.in/code)
- ✅ Real-time performance tracking
- ✅ Commission tier visibility (₹30/₹50/₹75)

### Admin Features
- ✅ View all influencers & performance
- ✅ Adjust discount ceilings per influencer
- ✅ View all coupons
- ✅ Marketing stats dashboard
- ✅ Revenue & order tracking

## File Structure

```
marketing/
  signup.html          ← Public influencer registration
  login.html           ← Influencer login
  dashboard.html       ← Influencer dashboard (create coupons, view stats)
  admin.html           ← Admin marketing panel
  README.md            ← This file
```

## Database Schema

Location: `sql/04_marketing_schema.sql`

Key tables:
- `campaigns` - Marketing campaigns
- `influencers` - Partner profiles
- `coupons` - Discount codes with tracking
- `coupon_usage` - Redemption history
- `influencer_clicks` - Click tracking
- `commissions` - Monthly payouts

## Deployment Checklist

### 1. Deploy SQL Schema
```bash
# Run on Supabase dev project
psql -h db.qkokywblwqdokoijutlb.supabase.co -U postgres -f sql/04_marketing_schema.sql
```

### 2. Upload Files to Hostinger
```
dev.absolutefreshfood.com/
  marketing/
    signup.html
    login.html
    dashboard.html
    admin.html
```

### 3. Test Flow
1. Visit dev.absolutefreshfood.com/marketing/signup.html
2. Register as influencer
3. Login at marketing/login.html
4. Create coupon with 20% discount
5. Check admin panel at marketing/admin.html

### 4. Admin Access
Admin panel: dev.absolutefreshfood.com/marketing/admin.html
Login with sales ops admin credentials (redirects if not admin)

## Integration Points

### With Sales Ops System
- **Shared `orders` table** - D2C orders have `coupon_id` populated
- **Driver interface** - sees both B2B and D2C orders
- **Admin dashboard** - toggle between Sales Ops and Marketing views

### Coupon Redemption Flow
```
Customer → Website checkout → Applies PRIYA20
  ↓
Order created with coupon_id
  ↓
Influencer stats updated (total_orders, total_revenue)
  ↓
Commission calculated monthly
```

## Commission Structure

| Tier | Orders/Month | Rate |
|------|--------------|------|
| 🥉 Bronze | 1-10 | ₹30/order |
| 🥈 Silver | 11-30 | ₹50/order |
| 🥇 Gold | 31+ | ₹75/order |

Calculated on delivered orders only. COD rejections excluded.

## Discount Ceiling Logic

- **Default:** 25% (all new influencers)
- **Admin adjusts** based on performance
- **System enforces:** Influencer cannot create coupon above their ceiling
- **Example:** Ceiling 30% → can create 10%, 20%, 25%, 30% but not 35%

## Phase 2 Features (Not Yet Built)

- Content approval workflow
- Sample request system
- WhatsApp notifications
- Advanced analytics dashboard
- Campaign management UI
- Automated commission payouts
- TDS calculation

## URLs

**Public Pages:**
- Signup: /marketing/signup.html
- Login: /marketing/login.html

**Protected Pages:**
- Influencer Dashboard: /marketing/dashboard.html
- Admin Panel: /marketing/admin.html

## Notes

- Login uses localStorage (temporary solution)
- QR codes generated client-side via qrcode.js
- Short links hardcoded as `af.in/code` (domain not yet set up)
- Commission calculation manual for now (run SQL query monthly)

## Next Steps After Deployment

1. Set up af.in domain with URL shortener
2. Build WhatsApp notification edge function
3. Create commission payout workflow
4. Add content approval UI
5. Build sample request system
