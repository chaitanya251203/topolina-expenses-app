import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {webcrypto} from 'node:crypto';
import ts from 'typescript';
import assert from 'node:assert/strict';
globalThis.crypto??=webcrypto;
const source=await readFile(new URL('../../supabase/functions/manage-users/index.ts',import.meta.url),'utf8');
const {outputText}=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}});
const {handle}=await import('data:text/javascript;base64,'+Buffer.from(outputText).toString('base64'));
const env=(key)=>({SUPABASE_URL:'https://test.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'private-test-only'})[key];
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json'}});
function backend({role='admin',active=true,valid=true}={}){
  let account;const calls=[];
  const send=async(url,options={})=>{
    const path=new URL(url).pathname;calls.push(path);
    if(path==='/auth/v1/user')return json({id:'admin'},valid?200:401);
    if(path.endsWith('/session_context'))return json({id:'admin',role_code:role,active});
    if(path.endsWith('/find_auth_user'))return json(account?.id??null);
    if(path.endsWith('/provision_waiter')||path.endsWith('/log_password_reset'))return new Response(null,{status:204});
    if(path.endsWith('/list_users'))return json([{id:'waiter',role_code:'waiter'},{id:'admin',role_code:'admin'}]);
    if(path==='/auth/v1/admin/users') {account={id:'waiter',...JSON.parse(options.body)};return json(account);}
    if(path==='/auth/v1/admin/users/waiter')return json(account??{id:'waiter'});
    throw new Error('Unexpected endpoint');
  };return {send,calls};
}
const body={action:'create',name:'Waiter',email:'waiter@example.invalid',password:'Test-only-password',request_id:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'};
const request=(data=body,token=true)=>new Request('https://test.invalid/functions/manage-users',{method:'POST',headers:{...(token?{Authorization:'Bearer test'}:{}),'Content-Type':'application/json'},body:JSON.stringify(data)});
test('account handler verifies live Auth session and admin status before privileged actions',async()=>{
  for(const fixture of [{role:'waiter'},{active:false},{valid:false}]){
    const b=backend(fixture);assert.ok([401,403].includes((await handle(request(),env,b.send)).status));
    assert.equal(b.calls.some(c=>c.startsWith('/auth/v1/admin')),false);
  }
  const b=backend();assert.equal((await handle(request(body,false),env,b.send)).status,401);assert.equal(b.calls.length,0);
});
test('create accepts empty void RPC responses, retries unchanged payload and rejects changed password',async()=>{
  const b=backend();assert.equal((await handle(request(),env,b.send)).status,200);
  assert.equal((await handle(request(),env,b.send)).status,200);
  assert.equal((await handle(request({...body,password:'Changed-password'}),env,b.send)).status,409);
  assert.equal(b.calls.filter(c=>c==='/auth/v1/admin/users').length,1);
});
test('password reset can target only waiter accounts and never returns server credentials',async()=>{
  const b=backend();assert.equal((await handle(request({action:'reset',user_id:'admin',password:'Test-only'}),env,b.send)).status,403);
  const response=await handle(request({action:'reset',user_id:'waiter',password:'Test-only'}),env,b.send);
  assert.equal(response.status,200);assert.equal((await response.text()).includes('private-test-only'),false);
});
