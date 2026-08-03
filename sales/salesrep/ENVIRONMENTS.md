# Environments — Absolute Fresh Food Sales App

## Two environments

| | DEV | PROD |
|---|---|---|
| Purpose | Testing, building | Live operations |
| Supabase project | fbfopgzblqmsflkfejwa | Create new project |
| URL | localhost / file:// | https://yourdomain.com |
| Data | Test data, can delete anytime | Real orders, never delete |

## How to switch

Open `js/app.js` — line 16:

```javascript
const ACTIVE_ENV = 'dev';   // ← development
const ACTIVE_ENV = 'prod';  // ← production
```

When on DEV you'll see a small **⚙ DEV** badge in the bottom left corner.
When on PROD the badge disappears.

## Setting up PROD

1. Create new Supabase project at supabase.com
   - Name: AFF-Production
   - Region: Southeast Asia (Singapore)
   - Strong database password

2. Run `sql/01_schema.sql` in the new project's SQL Editor

3. Create admin user:
   - Supabase → Authentication → Users → Add user
   - ✅ Auto Confirm User

4. Run `sql/03_prod_setup.sql`

5. Update `js/app.js`:
```javascript
prod: {
  url:  'https://YOUR_NEW_PROJECT_ID.supabase.co',
  anon: 'YOUR_NEW_ANON_KEY',
  label: 'PROD'
}
```

6. Change `ACTIVE_ENV = 'prod'`

7. Upload entire AFF folder to Hostinger public_html/

## Rule

- **Never test on PROD** — always use DEV for new features
- **Never copy prod data to dev** — use fake test data in dev
- **Deploy to prod only when tested** — full flow verified in dev first

## Deployment steps (when ready to push an update)

1. Test change in DEV — full flow
2. Change `ACTIVE_ENV = 'prod'`
3. Upload changed files to Hostinger via FTP/File Manager
4. Test on live URL
5. Change `ACTIVE_ENV = 'dev'` for next development session
