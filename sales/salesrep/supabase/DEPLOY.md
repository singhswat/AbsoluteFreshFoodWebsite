# Deploy Edge Function — create-user

This function lets admins create users securely from the HTML page.
The service role key stays on Supabase servers — never exposed in browser.

## Deploy Steps (one time, takes 3 minutes)

### Option A — Supabase Dashboard (easiest)

1. Go to supabase.com → your project → Edge Functions
2. Click "New Function"
3. Name: `create-user`
4. Paste the contents of `supabase/functions/create-user/index.ts`
5. Click Deploy

### Option B — Supabase CLI

Install CLI and run:
```bash
npm install -g supabase
supabase login
supabase functions deploy create-user --project-ref fbfopgzblqmsflkfejwa
```

## After Deploying

The Team page will work immediately — admins can create reps and drivers
directly from the browser without touching Supabase dashboard.

## Security

- Only authenticated admins can call this function
- Service role key is stored as a Supabase secret (never in your HTML)
- All user creation is logged
