// Privileged Auth actions run only here. No service key is shipped in the app.
const headers = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info' };
export async function handle(request: Request, env: (key: string) => string | undefined, send = fetch): Promise<Response> {
  const reply = (status: number, message: string) => new Response(JSON.stringify({ message }), { status, headers });
  if (request.method === 'OPTIONS') return reply(200, 'ok');
  if (request.method !== 'POST') return reply(405, 'Use POST.');
  try {
    const url = env('SUPABASE_URL')!, key = env('SUPABASE_ANON_KEY')!, service = env('SUPABASE_SERVICE_ROLE_KEY')!;
    if (!url || !key || !service) return reply(503, 'Account management is not configured.');
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) return reply(401, 'Sign in to continue.');
    const userHeaders = { apikey: key, Authorization: authorization, 'Content-Type': 'application/json' };
    // Verify the token with Auth; never trust decoded JWT claims alone.
    if (!(await send(`${url}/auth/v1/user`, { headers: userHeaders })).ok) return reply(401, 'Your session has expired. Sign in again.');
    const rpc = async (name: string, body: unknown) => {
      const result = await send(`${url}/rest/v1/rpc/${name}`, { method: 'POST', headers: userHeaders, body: JSON.stringify(body) });
      if (!result.ok) throw new Error('Account action could not be completed. Refresh and try again.');
      const text=await result.text();
      return text.trim()?JSON.parse(text):null;
    };
    const profile = await rpc('session_context', {});
    if (!profile.active || profile.role_code !== 'admin') return reply(403, 'Administrator access required.');
    const raw = await request.text();
    if (raw.length > 5000) return reply(400, 'Request too large.');
    const body = JSON.parse(raw);
    if (typeof body.password !== 'string' || body.password.length < 8 || new TextEncoder().encode(body.password).length > 72) return reply(400, 'Use a password of at least 8 characters and at most 72 bytes.');
    const adminHeaders = { apikey: service, Authorization: `Bearer ${service}`, 'Content-Type': 'application/json' };
    if (body.action === 'create') {
      const email = String(body.email ?? '').trim(), name = String(body.name ?? '').trim(), requestId = String(body.request_id ?? '');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !name || name.length > 120 || !/^[0-9a-f-]{36}$/i.test(requestId)) return reply(400, 'Enter a valid email, name and request reference.');
      const encoder=new TextEncoder();
      const hmacKey=await crypto.subtle.importKey('raw',encoder.encode(service),{name:'HMAC',hash:'SHA-256'},false,['sign']);
      const fingerprint=Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',hmacKey,encoder.encode(JSON.stringify([email.toLowerCase(),name,body.password]))))).map(b=>b.toString(16).padStart(2,'0')).join('');
      let id = await rpc('find_auth_user', { p_email: email });
      if (id) {
        const existing = await send(`${url}/auth/v1/admin/users/${id}`, { headers: adminHeaders });
        const data = await existing.json();
        if (!existing.ok || data.app_metadata?.topolina_request !== requestId || data.app_metadata?.topolina_actor !== profile.id || data.app_metadata?.topolina_fingerprint!==fingerprint) return reply(409, 'An account with this email already exists.');
      } else {
        const created = await send(`${url}/auth/v1/admin/users`, { method: 'POST', headers: adminHeaders, body: JSON.stringify({ email, password: body.password,
          email_confirm: true, app_metadata: { topolina_request: requestId, topolina_actor: profile.id,topolina_fingerprint:fingerprint } }) });
        if (!created.ok) return reply(400, 'Unable to create this account. Check the email and password, or refresh if it already exists.');
        id = (await created.json()).id;
      }
      await rpc('provision_waiter', { p_user_id: id, p_name: name });
      return reply(200, 'Waiter account is ready.');
    }
    if (body.action === 'reset') {
      const accounts = await rpc('list_users', {});
      if (!accounts.some((u: { id: string; role_code: string }) => u.id === body.user_id && u.role_code === 'waiter')) return reply(403, 'Choose a waiter account.');
      const changed = await send(`${url}/auth/v1/admin/users/${body.user_id}`, { method: 'PUT', headers: adminHeaders, body: JSON.stringify({ password: body.password }) });
      if (!changed.ok) return reply(400, 'Unable to change the password.');
      await rpc('log_password_reset', { p_user_id: body.user_id });
      return reply(200, 'Password updated.');
    }
    return reply(400, 'Unknown account action.');
  } catch { return reply(400, 'Account action failed. Check your connection and try again.'); }
}
if (import.meta.main) Deno.serve((request: Request) => handle(request, (key) => Deno.env.get(key)));
