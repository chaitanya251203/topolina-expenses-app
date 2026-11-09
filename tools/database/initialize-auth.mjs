// One-time operator tool. Credentials are accepted only through the process
// environment and are never saved or printed. This is not shipped in the APK.
import https from 'node:https';
import { Resolver } from 'node:dns';
import { readFile } from 'node:fs/promises';

const config = JSON.parse(await readFile(new URL('../../config/supabase.local.json', import.meta.url), 'utf8'));
const email = process.env.TOPOLINA_ADMIN_EMAIL;
const password = process.env.TOPOLINA_ADMIN_PASSWORD;
const action = process.argv[2] ?? 'verify';
if (!email || !password || !['create','verify'].includes(action)) throw new Error('Provide an email, password and create/verify action.');
const resolver = new Resolver();
if (process.env.TOPOLINA_DNS_SERVER) resolver.setServers([process.env.TOPOLINA_DNS_SERVER]);
const url = new URL(action === 'create' ? '/auth/v1/signup' : '/auth/v1/token?grant_type=password', config.SUPABASE_URL);
const data = JSON.stringify({ email, password });

try {
  const response = await new Promise((resolve, reject) => {
    const options = { method: 'POST', headers: {
      apikey: config.SUPABASE_PUBLISHABLE_KEY, 'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data),
    }};
    if (process.env.TOPOLINA_DNS_SERVER) options.lookup = (host, opts, callback) => {
      resolver.resolve4(host, (error, addresses) => {
        if (error) return callback(error);
        callback(null, opts.all ? addresses.map(address=>({ address, family:4 })) : addresses[0], 4);
      });
    };
    const request = https.request(url, options, result => {
      let body=''; result.on('data', chunk=>body+=chunk);
      result.on('end',()=>resolve({status:result.statusCode, body:JSON.parse(body)}));
    });
    request.setTimeout(15000,()=>request.destroy(new Error('timeout')));
    request.on('error',reject); request.end(data);
  });
  if (response.status >= 400) {
    console.error(`Authentication operation failed (${response.body.error_code ?? response.body.code ?? response.status}).`);
    process.exitCode=1;
  } else {
    console.log(action === 'create'
      ? (response.body.access_token ? 'Account created and authenticated.' : 'Account created; email confirmation is required.')
      : 'Admin login verified.');
  }
} catch (error) {
  console.error(`Authentication connection failed (${error.code ?? error.name}).`);
  process.exitCode=1;
}
