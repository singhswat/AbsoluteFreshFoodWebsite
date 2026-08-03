# 🥬 Absolute Fresh Food — Sales Operations

Simple HTML app. No build step. No compilation. Works in any browser.

## Files

```
index.html              ← Login page (start here)
pages/
  dashboard.html        ← Admin live dashboard
  beatplan.html         ← Admin beat plan builder
  beat.html             ← Rep today's beat + order entry
  deliveries.html       ← Driver pending deliveries
css/style.css           ← All styles
js/app.js               ← Shared JS + Supabase config
sql/
  01_schema.sql         ← Run first in Supabase
  02_seed_admin.sql     ← Run after creating admin user
```

## Setup (15 minutes)

### Step 1 — Create Supabase project
1. Go to supabase.com → New project
2. Region: Southeast Asia (Singapore)
3. Copy your **Project URL** and **Anon Key**

### Step 2 — Add your Supabase credentials
Open `js/app.js` and replace:
```javascript
const SUPABASE_URL  = 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON = 'YOUR_ANON_KEY';
```

### Step 3 — Run SQL schema
Supabase → SQL Editor → paste `sql/01_schema.sql` → Run

### Step 4 — Create admin user
Supabase → Authentication → Users → Add user
- Email: admin@absolutefreshfood.com
- Password: Admin@123
- ✅ Tick "Auto Confirm User"

Then run `sql/02_seed_admin.sql` in SQL Editor

### Step 5 — Upload to Hostinger
Upload all files to your Hostinger `public_html/` folder via File Manager or FTP.

### Step 6 — Open the app
Go to your domain → login with admin@absolutefreshfood.com / Admin@123

## Adding your team
1. Go to `yoursite.com/pages/team.html`
2. Click "Add User" → fill in name, email, role
3. OR share the Register link — team members register themselves

## Daily workflow
```
Admin (monthly)  → beatplan.html → Create plans → Add outlets → Publish
Rep (daily)      → beat.html     → See outlets → Tap Order → Submit
Driver (daily)   → deliveries.html → See orders → Confirm delivery
Admin (anytime)  → dashboard.html → Live stats → Fill rates
```
