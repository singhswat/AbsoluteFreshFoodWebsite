// WhatsApp Business API alert function
// Deploy to Supabase Edge Functions
// Required secrets: WHATSAPP_TOKEN, WHATSAPP_PHONE_ID

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { type, record } = await req.json();
    const sb = createClient(Deno.env.get('SUPABASE_URL')??'', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'');
    const { data: s } = await sb.from('app_settings').select('value').eq('key','whatsapp_number').single();
    if (!s?.value) return new Response('No number', { status: 200 });
    const msgs = {
      new_order:  `🛒 New order: ${record.outlet_name} — ${record.kg} kg (${record.rep})`,
      overdue:    `⚠️ Overdue delivery: ${record.outlet_name} not delivered`,
      beat_late:  `⏰ Beat not confirmed: ${record.rep_name}`,
      short_del:  `📦 Short delivery: ${record.outlet_name} got ${record.kg_del}/${record.kg_ord} kg`
    };
    const msg = msgs[type] || type;
    const token = Deno.env.get('WHATSAPP_TOKEN');
    const phoneId = Deno.env.get('WHATSAPP_PHONE_ID');
    if (token && phoneId) {
      await fetch(`https://graph.facebook.com/v17.0/${phoneId}/messages`, {
        method:'POST',
        headers:{'Authorization':`Bearer ${token}`,'Content-Type':'application/json'},
        body: JSON.stringify({ messaging_product:'whatsapp', to:s.value.replace(/\D/g,''), type:'text', text:{body:msg} })
      });
    }
    await sb.from('whatsapp_logs').insert({ trigger:type, recipient:s.value, message:msg, status:'sent' });
    return new Response(JSON.stringify({ok:true}), { headers:{...cors,'Content-Type':'application/json'} });
  } catch(e) {
    return new Response(JSON.stringify({error:e.message}), { status:500, headers:{...cors,'Content-Type':'application/json'} });
  }
});
