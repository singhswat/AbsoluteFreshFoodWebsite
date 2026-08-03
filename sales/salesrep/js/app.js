// ── Environment Config ─────────────────────────────────────
const ENV = {
  dev: {
    url:  'https://fbfopgzblqmsflkfejwa.supabase.co',
    anon: 'sb_publishable_r7mYhsyIKtBjBKzxH8St9g_OHjTU-RQ',
    label: 'DEV'
  },
  prod: {
    url:  'https://YOUR_PROD_PROJECT.supabase.co',
    anon: 'YOUR_PROD_ANON_KEY',
    label: 'PROD'
  }
};

// ── Switch environment here ─────────────────────────────────
// Change to 'prod' when going live
const ACTIVE_ENV = 'dev';

const SUPABASE_URL  = ENV[ACTIVE_ENV].url;
const SUPABASE_ANON = ENV[ACTIVE_ENV].anon;

// No dev/prod theming needed — single environment

const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON);

// ── Auth helpers ────────────────────────────────────────────
async function getUser() {
  // Use unified session from aff_session (set by login.html)
  try {
    const raw = sessionStorage.getItem('aff_session');
    if (raw) {
      const s = JSON.parse(raw);
      if (s && (s.role === 'rep' || s.role === 'driver' || s.role === 'admin')) return s;
    }
  } catch(e) {}
  return null;
}

async function signOut() {
  sessionStorage.removeItem('aff_session');
  sessionStorage.removeItem('aff_admin');
  localStorage.clear();
  // Redirect to unified login (two levels up from /salesrep/pages/, one from /salesrep/)
  const depth = window.location.pathname.includes('/pages/') ? '../../' : '../';
  window.location.href = depth + 'login.html';
}

// ── UI helpers ──────────────────────────────────────────────
function showError(id, msg) {
  const el = document.getElementById(id);
  if (el) { el.textContent = msg; el.style.display = 'block'; }
}

function hideError(id) {
  const el = document.getElementById(id);
  if (el) el.style.display = 'none';
}

function showToast(msg, type = 'success') {
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3000);
}

function loading(btn, isLoading, text = 'Save') {
  if (!btn) return;
  btn.disabled = isLoading;
  btn.textContent = isLoading ? '...' : text;
}

// ── i18n ────────────────────────────────────────────────────
const T = {
  en: {
    login: 'Sign In', email: 'Email', password: 'Password',
    dashboard: 'Dashboard', beat_plan: 'Beat Plan', orders: 'Orders',
    deliveries: 'Deliveries', collections: 'Collections', settings: 'Settings',
    today_beat: "Today's Beat", submit_order: 'Submit Order',
    kg_ordered: 'Kg Ordered', outlet: 'Outlet', confirm: 'Confirm',
    pending: 'Pending Deliveries', sign_out: 'Sign Out',
    total_ordered: 'Total Ordered', total_delivered: 'Total Delivered',
    fill_rate: 'Fill Rate', collections_lbl: 'Collections',
    add_outlet: 'Add Outlet', publish: 'Publish', draft: 'Draft',
    save: 'Save', cancel: 'Cancel', loading: 'Loading...',
    no_data: 'No data yet', error: 'Something went wrong'
  },
  hi: {
    login: 'लॉग इन', email: 'ईमेल', password: 'पासवर्ड',
    dashboard: 'डैशबोर्ड', beat_plan: 'बीट प्लान', orders: 'ऑर्डर',
    deliveries: 'डिलीवरी', collections: 'कलेक्शन', settings: 'सेटिंग',
    today_beat: 'आज का बीट', submit_order: 'ऑर्डर दें',
    kg_ordered: 'किलो ऑर्डर', outlet: 'आउटलेट', confirm: 'कन्फर्म',
    pending: 'पेंडिंग डिलीवरी', sign_out: 'साइन आउट',
    total_ordered: 'कुल ऑर्डर', total_delivered: 'कुल डिलीवरी',
    fill_rate: 'फिल रेट', collections_lbl: 'कलेक्शन',
    add_outlet: 'आउटलेट जोड़ें', publish: 'पब्लिश', draft: 'ड्राफ्ट',
    save: 'सेव', cancel: 'रद्द', loading: 'लोड हो रहा है...',
    no_data: 'अभी कोई डेटा नहीं', error: 'कुछ गलत हुआ'
  }
};

let lang = localStorage.getItem('lang') || 'en';
function t(key) { return T[lang][key] || T.en[key] || key; }
function setLang(l) { lang = l; localStorage.setItem('lang', l); location.reload(); }

// ── Format helpers ───────────────────────────────────────────
const fmt = {
  kg:  n => `${(+n || 0).toFixed(1)} kg`,
  inr: n => `₹${(+n || 0).toLocaleString('en-IN')}`,
  pct: n => `${(+n || 0).toFixed(1)}%`,
  date: d => new Date(d).toLocaleDateString('en-IN', { day:'2-digit', month:'short' }),
  time: d => new Date(d).toLocaleTimeString('en-IN', { hour:'2-digit', minute:'2-digit' })
};

function fillRate(ordered, delivered) {
  if (!ordered || ordered === 0) return 0;
  return (delivered / ordered) * 100;
}

function fillClass(rate) {
  if (rate >= 95) return 'green';
  if (rate >= 90) return 'amber';
  return 'red';
}
