// Hosted Auth integration. No financial fixtures; temporary account is removed.
// Privileged cleanup key is read from the operator CLI in memory, never saved/logged.
import https from 'node:https';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import assert from 'node:assert/strict';
const config=JSON.parse(await readFile(new URL('../../config/supabase.local.json',import.meta.url),'utf8'));
const root=new URL(config.SUPABASE_URL),apiKey=config.SUPABASE_PUBLISHABLE_KEY;
const dns=await fetch(`https://dns.google/resolve?name=${encodeURIComponent(root.hostname)}&type=A`).then(r=>r.json());
const ips=dns.Answer?.filter(a=>a.type===1).map(a=>a.data);assert.ok(ips?.length);
function request(path,body,{token,key=apiKey,method='POST'}={}){
  return new Promise((resolve,reject)=>{
    const data=body===undefined?undefined:JSON.stringify(body);
    const req=https.request(new URL(path,root),{method,headers:{apikey:key,...(token?{Authorization:`Bearer ${token}`}:{ }),...(data?{'Content-Type':'application/json','Content-Length':Buffer.byteLength(data)}:{})},
      lookup:(_host,options,cb)=>cb(null,options.all?ips.map(address=>({address,family:4})):ips[0],4)},res=>{let text='';res.on('data',c=>text+=c);res.on('end',()=>{try{resolve({status:res.statusCode,data:text?JSON.parse(text):null});}catch{reject(new Error('Invalid service response'));}});});
    req.on('error',reject);req.setTimeout(20000,()=>req.destroy(new Error('timeout')));req.end(data);
  });
}
const cli=spawnSync('cmd.exe',['/d','/s','/c','npx --yes supabase projects api-keys --remote=frpekgewxpdzcikpzsit --reveal --output=json'],{encoding:'utf8',windowsHide:true});
if(cli.status!==0)throw new Error('Operator login is required for test account cleanup.');
const keys=JSON.parse(cli.stdout),service=keys.find(k=>k.name==='service_role')?.api_key;
assert.ok(service,'A cleanup credential is required before creating a test user.');
const client=new pg.Client({host:process.env.PGHOST,user:process.env.PGUSER,password:process.env.PGPASSWORD,database:'postgres',ssl:{rejectUnauthorized:true}});
let temporaryId,adminToken,waiterToken;
const email=`topolina-qa-${randomUUID()}@example.invalid`,password=`Qa!${randomUUID()}`,second=`Qa!${randomUUID()}`;
try{
  await client.connect();
  const login=await request('/auth/v1/token?grant_type=password',{email:process.env.TOPOLINA_ADMIN_EMAIL,password:process.env.TOPOLINA_ADMIN_PASSWORD});
  assert.equal(login.status,200,'Admin sign-in failed');adminToken=login.data.access_token;
  assert.equal((await request('/functions/v1/manage-users',{action:'create',email,password,name:'Temporary validation',request_id:randomUUID()})).status,401);
  const requestId=randomUUID(),body={action:'create',email,password,name:'Temporary validation',request_id:requestId};
  const created=await request('/functions/v1/manage-users',body,{token:adminToken});assert.equal(created.status,200,'Account creation failed');
  temporaryId=(await client.query('select id from auth.users where email=$1',[email])).rows[0]?.id;assert.ok(temporaryId);
  assert.equal((await request('/functions/v1/manage-users',body,{token:adminToken})).status,200,'Identical account retry failed');
  let waiter=await request('/auth/v1/token?grant_type=password',{email,password});assert.equal(waiter.status,200);waiterToken=waiter.data.access_token;
  const context=await request('/rest/v1/rpc/session_context',{}, {token:waiterToken});assert.equal(context.data.role_code,'waiter');
  assert.equal((await request('/functions/v1/manage-users',{action:'reset',user_id:login.data.user.id,password:second},{token:waiterToken})).status,403);
  assert.equal((await request('/rest/v1/rpc/get_report',{p_from:'2020-01-01',p_to:'2020-01-01'},{token:waiterToken})).status,403);
  assert.equal((await request('/functions/v1/manage-users',{action:'reset',user_id:temporaryId,password:second},{token:adminToken})).status,200);
  waiter=await request('/auth/v1/token?grant_type=password',{email,password:second});assert.equal(waiter.status,200);waiterToken=waiter.data.access_token;
  assert.ok([200,204].includes((await request('/rest/v1/rpc/update_waiter',{p_user_id:temporaryId,p_name:'Temporary validation',p_active:false},{token:adminToken})).status));
  assert.equal((await request('/rest/v1/rpc/entry_context',{}, {token:waiterToken})).status,403,'Deactivated session still had data access');
  console.log('Hosted account flow verified: admin authentication, create/retry, waiter login, password reset, admin isolation and immediate deactivation.');
}catch(error){console.error(`Account verification failed (${error.code??error.name}): ${error.message}`);process.exitCode=1;}
finally{
  // Locate even if a response was lost after server creation.
  try{
    temporaryId??=(await client.query('select id from auth.users where email=$1',[email])).rows[0]?.id;
    if(temporaryId){
      await client.query('begin');await client.query('delete from public.profiles where id=$1',[temporaryId]);
      await client.query("delete from public.audit_logs where table_name='profiles' and record_id=$1",[temporaryId]);await client.query('commit');
      const removed=await request(`/auth/v1/admin/users/${temporaryId}`,undefined,{key:service,token:service,method:'DELETE'});assert.equal(removed.status,200);
      console.log('Temporary validation account removed; no test financial data created.');
    }
    for(const token of [adminToken,waiterToken].filter(Boolean))await request('/auth/v1/logout?scope=local',undefined,{token});
  }catch{console.error('Temporary account cleanup needs operator attention.');process.exitCode=1;}
  await client.end();
}
